import Foundation
import CryptoKit
import Darwin

/// Owner-approved removal of ONE historical test only. No directory discovery,
/// recursive deletion, index/preference writes, reset, or implicit installation.
enum ProbeOwnedAnimeCleanup {
    static let descriptor = "BE2EE206-9948-4F2B-BD3E-C02042EDBC5D"
    static let journalID = "B6DDAE7B-791A-4618-A85E-D9AC55BDF09E"
    static let parentRelative = ProbeInstallTest.store + "/61/Extensions/" + ProbeInstallTest.provider + "/descriptors"
    static let relative = parentRelative + "/" + descriptor

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func fail(_ message: String) -> NSError {
        PosterBoardStore.failure("Owned Anime cleanup refused: " + message + " Preserve the journal and log; do not retry blindly.")
    }
    static func validateRecord(_ data: Data, path: String) throws {
        guard let record = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let recorded = record["container"] as? String,
              try PosterBoardStore.canonicalContainer(recorded) == path,
              record["relative"] as? String == relative,
              record["archiveSHA256"] as? String == ProbeInstallTest.approvedSHA256,
              record["sourceIdentifier"] as? String == "7400",
              record["expected"] as? [String: String] == ApprovedAnimeManifest.files,
              record["normalizedIdentifier"] == nil,
              record["existingFilesModified"] as? Bool == false,
              record["preferencesModified"] as? Bool == false,
              record["registrationIPC"] as? Bool == false,
              record["galleryVerified"] as? Bool == false else {
            throw fail("exact historical journal identity/manifest differs.")
        }
    }
    static func localRead(_ url: URL, limit: Int) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { throw fail("required local evidence is unavailable.") }
        defer { close(fd) }
        return try readFile(fd, limit: limit)
    }
    static func readFile(_ fd: Int32, limit: Int) throws -> Data {
        var st = stat()
        guard fstat(fd, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG,
              st.st_nlink == 1, st.st_size >= 0, st.st_size <= limit,
              lseek(fd, 0, SEEK_SET) == 0 else { throw fail("nonregular, linked, oversized or unreadable file.") }
        var bytes = [UInt8](repeating: 0, count: Int(st.st_size) + 1)
        var total = 0
        while total < bytes.count {
            let got = bytes.withUnsafeMutableBytes {
                Darwin.read(fd, $0.baseAddress!.advanced(by: total), $0.count - total)
            }
            if got < 0 && errno == EINTR { continue }
            guard got >= 0 else { throw fail("file read failed.") }
            if got == 0 { break }
            total += got
        }
        var after = stat()
        guard total == Int(st.st_size), fstat(fd, &after) == 0,
              after.st_size == st.st_size, same(st, after),
              after.st_mtimespec.tv_sec == st.st_mtimespec.tv_sec,
              after.st_mtimespec.tv_nsec == st.st_mtimespec.tv_nsec else { throw fail("file changed during read.") }
        return Data(bytes.prefix(total))
    }
    static func same(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && (a.st_mode & S_IFMT) == (b.st_mode & S_IFMT)
    }
    static func writeEvidence(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .withoutOverwriting)
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw fail("cannot open saved evidence.") }
        defer { close(fd) }
        guard fsync(fd) == 0, try readFile(fd, limit: max(data.count, 1)) == data else {
            throw fail("saved evidence sync/readback failed.")
        }
    }
    static func directorySync(_ url: URL) throws {
        let fd = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw fail("cannot open evidence directory.") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw fail("evidence directory sync failed.") }
    }

    static func run(path: String, log: @escaping (String) -> Void) throws {
        let canonical = try PosterBoardStore.canonicalContainer(path)
        guard canonical == path, try ProbeDiagnostics.identifiesPosterBoard(path, log: log) else {
            throw fail("strict PosterBoard identity is required.")
        }
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let journal = documents.appendingPathComponent("InstallTests").appendingPathComponent(journalID)
        for url in [documents, journal.deletingLastPathComponent(), journal] {
            let a = try fm.attributesOfItem(atPath: url.path)
            guard a[.type] as? FileAttributeType == .typeDirectory else { throw fail("local journal directory redirected.") }
        }
        let pending = journal.appendingPathComponent("pending.json")
        let record = try localRead(pending, limit: 65_536)
        try validateRecord(record, path: path)
        let archive = try localRead(journal.appendingPathComponent("original.tendies"), limit: 268_435_456)
        guard digest(archive) == ProbeInstallTest.approvedSHA256,
              String(data: try localRead(journal.appendingPathComponent("copy-pass.txt"), limit: 1024), encoding: .utf8)
                == "COPY PASS; gallery visibility and activation UNVERIFIED",
              String(data: try localRead(journal.appendingPathComponent("complete.txt"), limit: 1024), encoding: .utf8)
                == "COPY PASS and lease closed; gallery UNVERIFIED" else {
            throw fail("original archive or completed-copy ownership evidence differs.")
        }
        let lease = try PosterBoardLease(path: path, log: log)
        do {
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease, rule: .strict)
            // Fixed store61 only, never select newest store or scan another wallpaper.
            var grantPaths = Set<String>()
            for file in ApprovedAnimeManifest.files.keys {
                let components = (relative + "/" + file).split(separator: "/").map(String.init)
                for count in 1...components.count { grantPaths.insert(components.prefix(count).joined(separator: "/")) }
            }
            for part in grantPaths.sorted(by: { $0.count < $1.count }) {
                guard lease.grant(part), lease.permits(lease.effectiveURL.appendingPathComponent(part)) else {
                    throw fail("exact historical path access denied or redirected.")
                }
            }
            let parent = lease.effectiveURL.appendingPathComponent(parentRelative)
            guard lease.permits(parent) else { throw fail("historical parent redirected.") }
            let tree = try Tree(parent: parent, name: descriptor, expected: ApprovedAnimeManifest.files) {
                guard lease.permits(parent) else { throw fail("historical parent ancestry redirected.") }
            }
            let evidence = journal.appendingPathComponent("RemovalEvidence-" + UUID().uuidString)
            try fm.createDirectory(at: evidence, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try tree.backup(to: evidence)
            try writeEvidence(record, to: evidence.appendingPathComponent("pending-original.json"))
            let proof: [String: Any] = [
                "descriptor": descriptor, "journal": journalID, "relative": relative, "container": path,
                "archiveSHA256": ProbeInstallTest.approvedSHA256, "expected": ApprovedAnimeManifest.files,
                "rootInode": UInt64(tree.rootInfo.st_ino), "rootDevice": Int64(tree.rootInfo.st_dev),
                "note": "Exact prior test only. No preferences, indexes or other wallpapers authorized."
            ]
            try writeEvidence(JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]),
                              to: evidence.appendingPathComponent("proof.json"))
            try directorySync(evidence)
            try directorySync(journal)
            // Recheck mutable journal, container and all held directory/file identities.
            guard try localRead(pending, limit: 65_536) == record,
                  try ProbeDiagnostics.identifiesPosterBoard(path, log: log),
                  lease.permits(parent) else { throw fail("ownership/path changed before removal.") }
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease, rule: .strict)
            log("OWNED CLEANUP BEFORE · only descriptor=\(descriptor) journal=\(journalID); verified backup=\(evidence.lastPathComponent)")
            try tree.removeVerified()
            try writeEvidence(Data("Exact prior Anime descriptor removal verified; no other wallpaper/index/preferences touched.".utf8),
                              to: evidence.appendingPathComponent("removed.txt"))
            try directorySync(evidence)
            try lease.close()
            // Clear ONLY this journal's pending marker, AFTER removal and lease close.
            // Rename preserves original evidence instead of deleting the journal.
            guard try localRead(pending, limit: 65_536) == record else {
                throw fail("removed descriptor but pending journal changed; marker preserved.")
            }
            try fm.moveItem(at: pending, to: journal.appendingPathComponent("removed-owned-anime-pending.json"))
            try directorySync(journal)
            log("OWNED CLEANUP COMPLETE · exact old Anime descriptor absent; matching pending marker archived. Original journal/archive and verified backup retained. No automatic reinstall, index edit or refresh.")
        } catch {
            do { try lease.close() } catch { log("CLEANUP ERROR · \(error.localizedDescription)") }
            throw error
        }
    }

    /// Held directory descriptors and unlinkat avoid recursive deletion and
    /// symlink traversal. Changes/extra entries/hard links stop removal.
    final class Tree {
        let parentFD: Int32
        let rootFD: Int32
        let name: String
        let rootInfo: stat
        let parentURL: URL
        let parentInfo: stat
        let validatePath: () throws -> Void
        let expected: [String: String]
        var directories: [String: Int32] = [:]
        var identities: [String: stat] = [:]
        var contents: [String: Data] = [:]
        var removed = Set<String>()

        init(parent: URL, name: String, expected: [String: String], validatePath: @escaping () throws -> Void = {}) throws {
            guard !name.isEmpty, !name.contains("/"), name != ".", name != "..",
                  !expected.isEmpty, expected.count <= 64,
                  expected.keys.allSatisfy({ !$0.isEmpty && !$0.contains("\\") &&
                    $0.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." } }) else {
                throw ProbeOwnedAnimeCleanup.fail("invalid fixed manifest paths.")
            }
            try validatePath()
            self.validatePath = validatePath
            parentURL = parent
            self.name = name
            self.expected = expected
            let p = open(parent.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard p >= 0 else { throw ProbeOwnedAnimeCleanup.fail("cannot open exact parent.") }
            var parentStat = stat()
            guard fstat(p, &parentStat) == 0 else { close(p); throw ProbeOwnedAnimeCleanup.fail("parent identity unavailable.") }
            parentInfo = parentStat
            let r = openat(p, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard r >= 0 else { close(p); throw ProbeOwnedAnimeCleanup.fail("exact old descriptor missing/redirected.") }
            var st = stat()
            guard fstat(r, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR else {
                close(r); close(p); throw ProbeOwnedAnimeCleanup.fail("cannot identify exact directory.")
            }
            parentFD = p; rootFD = r; rootInfo = st
            directories[""] = r
            identities[""] = st
            do {
                try capture(relative: "", fd: r)
                guard contents.count == expected.count,
                      contents.values.reduce(0, { $0 + $1.count }) <= 134_217_728 else {
                    throw ProbeOwnedAnimeCleanup.fail("incomplete/oversized historical tree.")
                }
                try verifyRemaining()
            } catch {
                // Fully initialized reference has deterministic deinit fd cleanup.
                throw error
            }
        }
        deinit {
            for fd in directories.values { close(fd) }
            close(parentFD)
        }
        static func names(_ fd: Int32) throws -> Set<String> {
            let duplicate = dup(fd)
            guard duplicate >= 0 else { throw ProbeOwnedAnimeCleanup.fail("directory fd duplication failed.") }
            guard let stream = fdopendir(duplicate) else { close(duplicate); throw ProbeOwnedAnimeCleanup.fail("directory enumeration failed.") }
            defer { closedir(stream) }
            rewinddir(stream)
            var result = Set<String>()
            while true {
                errno = 0
                guard let entry = readdir(stream) else {
                    guard errno == 0 else { throw ProbeOwnedAnimeCleanup.fail("directory enumeration interrupted.") }
                    break
                }
                let capacity = MemoryLayout.size(ofValue: entry.pointee.d_name)
                let name = withUnsafePointer(to: &entry.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
                }
                if name != "." && name != ".." { result.insert(name) }
                guard result.count <= 128 else { throw ProbeOwnedAnimeCleanup.fail("too many historical entries.") }
            }
            return result
        }
        func wantedChildren(_ relative: String) -> Set<String> {
            let prefix = relative.isEmpty ? "" : relative + "/"
            return Set(expected.keys.filter { $0.hasPrefix(prefix) }.map {
                String($0.dropFirst(prefix.count).split(separator: "/")[0])
            })
        }
        func capture(relative: String, fd: Int32) throws {
            let names = try Self.names(fd)
            guard names == wantedChildren(relative) else { throw ProbeOwnedAnimeCleanup.fail("extra/missing historical entries.") }
            for name in names.sorted() {
                let path = relative.isEmpty ? name : relative + "/" + name
                var st = stat()
                guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0, st.st_dev == rootInfo.st_dev else {
                    throw ProbeOwnedAnimeCleanup.fail("historical entry identity unavailable.")
                }
                if let hash = expected[path] {
                    guard (st.st_mode & S_IFMT) == S_IFREG, st.st_nlink == 1 else {
                        throw ProbeOwnedAnimeCleanup.fail("historical file is linked/nonregular.")
                    }
                    let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
                    guard file >= 0 else { throw ProbeOwnedAnimeCleanup.fail("historical file inaccessible.") }
                    let bytes: Data
                    do {
                        defer { close(file) }
                        var held = stat()
                        guard fstat(file, &held) == 0, same(st, held) else { throw ProbeOwnedAnimeCleanup.fail("historical file replaced.") }
                        bytes = try readFile(file, limit: 16_777_216)
                    }
                    guard digest(bytes) == hash else { throw ProbeOwnedAnimeCleanup.fail("historical bytes differ; nothing deleted.") }
                    guard contents.values.reduce(bytes.count, { $0 + $1.count }) <= 134_217_728 else {
                        throw ProbeOwnedAnimeCleanup.fail("historical evidence exceeds bounded memory.")
                    }
                    contents[path] = bytes
                } else {
                    guard (st.st_mode & S_IFMT) == S_IFDIR else { throw ProbeOwnedAnimeCleanup.fail("historical directory redirected/nonregular.") }
                    let child = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                    guard child >= 0 else { throw ProbeOwnedAnimeCleanup.fail("historical directory inaccessible.") }
                    directories[path] = child
                    var held = stat()
                    guard fstat(child, &held) == 0, same(st, held) else { throw ProbeOwnedAnimeCleanup.fail("historical directory replaced.") }
                    try capture(relative: path, fd: child)
                }
                identities[path] = st
            }
        }
        func location(_ path: String) -> (Int32, String) {
            let parts = path.split(separator: "/").map(String.init)
            return (directories[parts.dropLast().joined(separator: "/")]!, parts.last!)
        }
        func verifyRemaining() throws {
            try validatePath()
            var currentParent = stat()
            guard lstat(parentURL.path, &currentParent) == 0, same(currentParent, parentInfo) else {
                throw ProbeOwnedAnimeCleanup.fail("historical parent moved/replaced.")
            }
            var root = stat()
            guard fstatat(parentFD, name, &root, AT_SYMLINK_NOFOLLOW) == 0, same(root, rootInfo) else {
                throw ProbeOwnedAnimeCleanup.fail("historical root moved/replaced.")
            }
            for (path, fd) in directories where !removed.contains(path) {
                let wanted = wantedChildren(path).filter {
                    !removed.contains(path.isEmpty ? $0 : path + "/" + $0)
                }
                guard try Self.names(fd) == Set(wanted) else { throw ProbeOwnedAnimeCleanup.fail("tree changed; remaining files preserved.") }
            }
            for (path, wanted) in identities where !path.isEmpty && !removed.contains(path) {
                let (fd, name) = location(path)
                var st = stat()
                guard fstatat(fd, name, &st, AT_SYMLINK_NOFOLLOW) == 0, same(st, wanted) else {
                    throw ProbeOwnedAnimeCleanup.fail("historical child replaced; remaining files preserved.")
                }
            }
        }
        func backup(to evidence: URL) throws {
            let fm = FileManager.default
            let backup = evidence.appendingPathComponent("descriptor-backup")
            try fm.createDirectory(at: backup, withIntermediateDirectories: false)
            for path in directories.keys.filter({ !$0.isEmpty }).sorted(by: { $0.count < $1.count }) {
                try fm.createDirectory(at: backup.appendingPathComponent(path), withIntermediateDirectories: false)
            }
            for (path, bytes) in contents {
                try writeEvidence(bytes, to: backup.appendingPathComponent(path))
            }
            for path in directories.keys.sorted(by: { $0.count > $1.count }) {
                try directorySync(backup.appendingPathComponent(path))
            }
            guard try PosterBoardStore.manifest(backup) == expected else { throw fail("backup manifest differs.") }
        }
        func removeVerified() throws {
            try verifyRemaining()
            // Read/hash every file again before the first mutation.
            for path in expected.keys.sorted() { try verifyFile(path) }
            for path in expected.keys.sorted() {
                try verifyRemaining()
                try verifyFile(path)
                let (fd, name) = location(path)
                guard unlinkat(fd, name, 0) == 0 else { throw fail("approved file removal failed; partial state/evidence retained.") }
                removed.insert(path)
            }
            for path in directories.keys.filter({ !$0.isEmpty }).sorted(by: { $0.count > $1.count }) {
                try verifyRemaining()
                let (fd, name) = location(path)
                guard unlinkat(fd, name, AT_REMOVEDIR) == 0 else { throw fail("approved empty directory removal failed.") }
                removed.insert(path)
            }
            try verifyRemaining()
            guard unlinkat(parentFD, name, AT_REMOVEDIR) == 0 else { throw fail("approved empty root removal failed.") }
            var st = stat()
            errno = 0
            guard fstatat(parentFD, name, &st, AT_SYMLINK_NOFOLLOW) == -1, errno == ENOENT else {
                throw fail("removal absence is unverified; pending marker preserved.")
            }
            guard fsync(parentFD) == 0 else { throw fail("historical parent sync failed; pending marker preserved.") }
        }
        func verifyFile(_ path: String) throws {
            let (fd, name) = location(path)
            let file = openat(fd, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
            guard file >= 0 else { throw fail("approved file no longer readable.") }
            defer { close(file) }
            var st = stat()
            guard let wanted = identities[path], fstat(file, &st) == 0, same(st, wanted),
                  digest(try readFile(file, limit: 16_777_216)) == expected[path] else {
                throw fail("approved file identity/hash changed; remaining files preserved.")
            }
        }
    }
}
