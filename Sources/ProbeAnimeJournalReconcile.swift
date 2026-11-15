import Foundation
import Darwin

/// Reconciles ONE own-app marker after fresh conservative read-only absence.
/// Never deletes or writes PosterBoard. Historical evidence is archived, not erased.
enum ProbeAnimeJournalReconcile {
    static let archivedName = "reconciled-absent-anime-pending.json"

    static func run(path: String, log: @escaping (String) -> Void) throws {
        guard try PosterBoardStore.canonicalContainer(path) == path,
              try ProbeDiagnostics.identifiesPosterBoard(path, log: log) else {
            throw failure("Strict PosterBoard identity required.")
        }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let local = try LocalJournal(documents: documents)
        try ProbeOwnedAnimeCleanup.validateRecord(local.record, path: path)
        // Require original completed-copy ownership evidence as well as the pinned manifest.
        guard ProbeOwnedAnimeCleanup.digest(try ProbeOwnedAnimeCleanup.localRead(
            local.url.appendingPathComponent("original.tendies"), limit: 268_435_456)) == ProbeInstallTest.approvedSHA256,
            try ProbeOwnedAnimeCleanup.localRead(local.url.appendingPathComponent("copy-pass.txt"), limit: 1024) ==
                Data("COPY PASS; gallery visibility and activation UNVERIFIED".utf8),
            try ProbeOwnedAnimeCleanup.localRead(local.url.appendingPathComponent("complete.txt"), limit: 1024) ==
                Data("COPY PASS and lease closed; gallery UNVERIFIED".utf8) else {
            throw failure("Historical completed-copy evidence differs.")
        }
        try local.validate()
        let evidence = try local.prepareEvidence(path: path)
        // All access acquisition and exact absence observations remain in the
        // existing diagnostic. It refuses presence/errors and closes its lease.
        let transcript = try ProbeAnimeAbsenceDiagnostic.run(path: path, log: log, requireAbsence: true)
        try local.validate()
        try ProbeOwnedAnimeCleanup.writeEvidence(Data(transcript.utf8),
            to: evidence.appendingPathComponent("absence-lease-closed.txt"))
        try ProbeOwnedAnimeCleanup.directorySync(evidence)
        try local.validate()
        try local.archiveMarker(evidence: evidence)
        log("JOURNAL RECONCILE PASS · exact B6DDAE7B pending marker archived after fresh exact ENOENT observations and successful lease close. Historical journal, original archive and absence proof preserved. No PosterBoard writes/removal, preferences, indexes or refresh. Test Install now requires a SEPARATE explicit confirmation; it has NOT run. Absence is a point-in-time observation, not a permanent guarantee.")
    }

    static func failure(_ message: String) -> NSError {
        PosterBoardStore.failure("Anime journal reconciliation refused: " + message + " Preserve evidence and Copy Log; no automatic install or retry.")
    }

    /// Hold every local directory and the exact pending inode. No-follow reads,
    /// identity/byte rechecks and exclusive same-directory rename fail closed.
    final class LocalJournal {
        let url: URL
        let record: Data
        let pendingFD: Int32
        let pendingInfo: stat
        let held: [(URL, Int32, stat)]
        var journalFD: Int32 { held.last!.1 }

        init(documents: URL) throws {
            let root = documents.appendingPathComponent("InstallTests")
            let journal = root.appendingPathComponent(ProbeOwnedAnimeCleanup.journalID)
            var opened = [(URL, Int32, stat)]()
            var file: Int32 = -1
            do {
                for location in [documents, root, journal] {
                    let fd: Int32
                    if let previous = opened.last {
                        fd = openat(previous.1, location.lastPathComponent, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                    } else { fd = open(location.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW) }
                    guard fd >= 0 else { throw failure("Local evidence directory unavailable or linked.") }
                    var info = stat()
                    guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
                        close(fd); throw failure("Local evidence directory invalid.")
                    }
                    opened.append((location, fd, info))
                }
                file = openat(opened.last!.1, "pending.json", O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
                guard file >= 0 else { throw failure("Exact pending marker unavailable or linked.") }
                var info = stat()
                guard fstat(file, &info) == 0, info.st_nlink == 1 else { throw failure("Pending marker linked/unreadable.") }
                let bytes = try ProbeOwnedAnimeCleanup.readFile(file, limit: 65_536)
                url = journal; held = opened; pendingFD = file; pendingInfo = info; record = bytes
            } catch {
                if file >= 0 { close(file) }
                for (_, fd, _) in opened { close(fd) }
                throw error
            }
            try validate()
        }
        deinit {
            close(pendingFD)
            for (_, fd, _) in held { close(fd) }
        }
        func validate() throws {
            for (location, fd, wanted) in held {
                var atPath = stat()
                var atFD = stat()
                guard lstat(location.path, &atPath) == 0, fstat(fd, &atFD) == 0,
                      ProbeOwnedAnimeCleanup.same(wanted, atPath),
                      ProbeOwnedAnimeCleanup.same(wanted, atFD) else {
                    throw failure("Local journal ancestry moved or redirected.")
                }
            }
            var marker = stat()
            guard fstatat(journalFD, "pending.json", &marker, AT_SYMLINK_NOFOLLOW) == 0,
                  ProbeOwnedAnimeCleanup.same(marker, pendingInfo), marker.st_nlink == 1,
                  try ProbeOwnedAnimeCleanup.readFile(pendingFD, limit: 65_536) == record else {
                throw failure("Exact pending marker identity/bytes changed.")
            }
            var archived = stat()
            let result = fstatat(journalFD, archivedName, &archived, AT_SYMLINK_NOFOLLOW)
            let savedError = errno
            guard result == -1, savedError == ENOENT else {
                throw failure("Archive destination exists or its absence is unverified.")
            }
        }
        func prepareEvidence(path: String) throws -> URL {
            try validate()
            let evidence = url.appendingPathComponent("AbsenceReconciliation-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            try ProbeOwnedAnimeCleanup.writeEvidence(record, to: evidence.appendingPathComponent("pending-original.json"))
            let proof: [String: Any] = [
                "journal": ProbeOwnedAnimeCleanup.journalID, "descriptor": ProbeOwnedAnimeCleanup.descriptor,
                "relative": ProbeOwnedAnimeCleanup.relative, "container": path,
                "pendingSHA256": ProbeOwnedAnimeCleanup.digest(record), "pendingInode": UInt64(pendingInfo.st_ino),
                "pendingDevice": Int64(pendingInfo.st_dev), "archiveName": archivedName,
                "scope": "Own-app journal only. Exact absence proof with lease close must exist before marker rename. No PosterBoard writes.",
                "installationPerformed": false
            ]
            try ProbeOwnedAnimeCleanup.writeEvidence(
                JSONSerialization.data(withJSONObject: proof, options: [.prettyPrinted, .sortedKeys]),
                to: evidence.appendingPathComponent("proof.json"))
            try ProbeOwnedAnimeCleanup.directorySync(evidence)
            try ProbeOwnedAnimeCleanup.directorySync(url)
            try validate()
            return evidence
        }
        func archiveMarker(evidence: URL) throws {
            try validate()
            let prefix = "AbsenceReconciliation-"
            guard evidence.deletingLastPathComponent() == url,
                  evidence.lastPathComponent.hasPrefix(prefix),
                  UUID(uuidString: String(evidence.lastPathComponent.dropFirst(prefix.count))) != nil else {
                throw failure("Reconciliation evidence location invalid.")
            }
            var directory = stat()
            guard lstat(evidence.path, &directory) == 0, (directory.st_mode & S_IFMT) == S_IFDIR,
                  try ProbeOwnedAnimeCleanup.localRead(evidence.appendingPathComponent("pending-original.json"), limit: 65_536) == record else {
                throw failure("Original marker evidence missing or changed.")
            }
            let saved = try ProbeOwnedAnimeCleanup.localRead(evidence.appendingPathComponent("proof.json"), limit: 65_536)
            guard let proof = try JSONSerialization.jsonObject(with: saved) as? [String: Any],
                  proof["journal"] as? String == ProbeOwnedAnimeCleanup.journalID,
                  proof["descriptor"] as? String == ProbeOwnedAnimeCleanup.descriptor,
                  proof["pendingSHA256"] as? String == ProbeOwnedAnimeCleanup.digest(record),
                  proof["archiveName"] as? String == archivedName,
                  let observation = String(data: try ProbeOwnedAnimeCleanup.localRead(
                    evidence.appendingPathComponent("absence-lease-closed.txt"), limit: 1_048_576), encoding: .utf8),
                  observation.components(separatedBy: "AUDIT ABSENCE CLASSIFICATION ENOENT_OBSERVED_EXACT_PATH").count >= 3,
                  observation.contains("AUDIT ABSENCE COMPLETE · lease closed; pending journal byte-identical") else {
                throw failure("Fresh validated-absence/lease-close proof unavailable.")
            }
            try validate()
            // RENAME_EXCL preserves any existing archive, including dangling links.
            guard renameatx_np(journalFD, "pending.json", journalFD, archivedName, UInt32(RENAME_EXCL)) == 0 else {
                throw failure("Exclusive own-app marker archival failed.")
            }
            var archived = stat()
            guard fstatat(journalFD, archivedName, &archived, AT_SYMLINK_NOFOLLOW) == 0,
                  ProbeOwnedAnimeCleanup.same(archived, pendingInfo),
                  try ProbeOwnedAnimeCleanup.readFile(pendingFD, limit: 65_536) == record,
                  fsync(journalFD) == 0 else {
                throw failure("Marker moved but archive verification/sync failed; evidence retained, installation stays blocked.")
            }
            var pending = stat()
            let result = fstatat(journalFD, "pending.json", &pending, AT_SYMLINK_NOFOLLOW)
            let savedError = errno
            guard result == -1, savedError == ENOENT else {
                throw failure("A pending marker appeared after archival; installation stays blocked.")
            }
        }
    }
}
