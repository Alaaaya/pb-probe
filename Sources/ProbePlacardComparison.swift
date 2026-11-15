import Foundation
import Darwin
import CryptoKit

/// Point-in-time, bounded, read-only observations, never proof of gallery acceptance.
enum ProbePlacardComparison {
    static let ours = "43E29B4A-89D5-4918-A641-EC162016FC8B"
    static let store = "Library/Application Support/PRBPosterExtensionDataStore/61"
    static let parent = store + "/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors"
    struct Entry {
        let path: String
        let details: String
        let hash: String?
        let text: String?
        let searchable: String
    }
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    static func decoded(_ data: Data) -> (String?, String) {
        if let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
           let xml = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0),
           let text = String(data: xml, encoding: .utf8) { return (text, text) }
        if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
           JSONSerialization.isValidJSONObject(object),
           let json = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted]),
           let text = String(data: json, encoding: .utf8) { return (text, text) }
        return (nil, String(decoding: data, as: UTF8.self))
    }
    static func run(path: String, log: @escaping (String) -> Void) throws -> String {
        let lease = try PosterBoardLease(path: path, log: log)
        do {
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease, rule: .strict)
            let report = try collect(base: lease.effectiveURL, allow: { relative in
                lease.grant(relative) && lease.permits(lease.effectiveURL.appendingPathComponent(relative))
            })
            try lease.close()
            log("AUDIT COMPARE COMPLETE · lease closed; point-in-time read-only snapshot. No install/remove/refresh/preferences/index writes. Candidates are content matches, NOT proof of Placard provenance or visibility.")
            return report
        } catch {
            do { try lease.close() } catch { log("CLEANUP ERROR · \(error.localizedDescription)") }
            throw error
        }
    }
    static func collect(base: URL, allow: (String) -> Bool) throws -> String {
        var entries: [String: Entry] = [:]
        var notes: [String] = []
        var count = 0
        var total = 0
        var exhausted = false
        // Parent-by-parent exact grants, no native/access implementation changes.
        let parts = store.split(separator: "/").map(String.init)
        for i in 1...parts.count {
            guard allow(parts.prefix(i).joined(separator: "/")) else {
                throw PosterBoardStore.failure("COMPARE existing bounded store grant denied/redirected")
            }
        }
        let root = base.appendingPathComponent(store)
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw PosterBoardStore.failure("COMPARE store61 open errno=\(errno)") }
        defer { close(fd) }
        var held = stat()
        guard fstat(fd, &held) == 0 else { throw PosterBoardStore.failure("COMPARE store fstat failed") }
        func walk(_ directory: Int32, _ relative: String, _ depth: Int) {
            guard depth <= 20, count < 8192 else { exhausted = true; return }
            let copied = dup(directory)
            guard copied >= 0 else { notes.append("DENIED dup \(relative)"); return }
            guard let stream = fdopendir(copied) else { close(copied); notes.append("DENIED list \(relative)"); return }
            defer { closedir(stream) }
            var names: [String] = []
            errno = 0
            while let item = readdir(stream) {
                let name = withUnsafePointer(to: &item.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name != "." && name != ".." {
                    guard names.count < 8192 else { exhausted = true; break }
                    names.append(name)
                }
                errno = 0
            }
            if errno != 0 { notes.append("DENIED readdir \(relative) errno=\(errno)") }
            for name in names.sorted() {
                guard count < 8192 else { exhausted = true; return }
                count += 1
                let child = relative + "/" + name
                guard !name.contains("/"), allow(child) else { notes.append("DENIED/REDIRECTED \(child)"); continue }
                var info = stat()
                guard fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                    notes.append("DENIED stat \(child) errno=\(errno)"); continue
                }
                let kind = info.st_mode & S_IFMT
                guard kind == S_IFDIR || kind == S_IFREG else { notes.append("SKIP nonregular/link \(child)"); continue }
                let current = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | (kind == S_IFDIR ? O_DIRECTORY : 0))
                guard current >= 0 else { notes.append("DENIED open \(child) errno=\(errno)"); continue }
                defer { close(current) }
                var actual = stat()
                guard fstat(current, &actual) == 0, actual.st_dev == info.st_dev,
                      actual.st_ino == info.st_ino, actual.st_mode == info.st_mode else {
                    notes.append("CHANGED \(child)"); continue
                }
                var data: Data?
                if kind == S_IFREG {
                    if info.st_size >= 0 && info.st_size <= 8_388_608 && total + Int(info.st_size) <= 100_663_296 {
                        var bytes = Data()
                        var buffer = [UInt8](repeating: 0, count: 65536)
                        var failed = false
                        while bytes.count <= 8_388_608 {
                            let got = Darwin.read(current, &buffer, buffer.count)
                            if got == 0 { break }
                            if got < 0 { failed = true; break }
                            bytes.append(contentsOf: buffer.prefix(got))
                        }
                        total += bytes.count
                        var after = stat()
                        if !failed && bytes.count == Int(info.st_size) && fstat(current, &after) == 0 &&
                            after.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec &&
                            after.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec &&
                            after.st_size == info.st_size { data = bytes }
                        else { notes.append("CHANGED/UNREADABLE \(child)") }
                    } else { notes.append("LIMIT payload unread \(child) bytes=\(info.st_size)"); exhausted = true }
                }
                let attrCount = flistxattr(current, nil, 0, 0)
                var attrs = "unavailable errno=\(errno)"
                if attrCount >= 0 && attrCount <= 65536 {
                    var raw = [CChar](repeating: 0, count: max(1, attrCount))
                    let got = flistxattr(current, &raw, raw.count, 0)
                    if got >= 0 && got <= attrCount {
                        attrs = raw.prefix(got).split(separator: 0).map {
                            String(decoding: $0.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                        }.sorted().joined(separator: ",")
                    }
                }
                // iOS Foundation reports the human-readable protection class.
                // Cross-check path still denotes the held fd before using it.
                var check = stat()
                var protection = "unavailable"
                if allow(child), fstatat(directory, name, &check, AT_SYMLINK_NOFOLLOW) == 0,
                   check.st_dev == info.st_dev, check.st_ino == info.st_ino {
                    #if os(iOS)
                    protection = (try? FileManager.default.attributesOfItem(atPath: base.appendingPathComponent(child).path)[.protectionKey])
                        .map { String(describing: $0) } ?? "unavailable"
                    #else
                    protection = "not iOS"
                    #endif
                }
                let unpacked = data.map(decoded)
                let details = "type=\(kind == S_IFDIR ? "dir" : "file") bytes=\(info.st_size) mode=\(String(info.st_mode, radix: 8)) uid=\(info.st_uid) gid=\(info.st_gid) mtime=\(info.st_mtimespec.tv_sec).\(String(format: "%09d", info.st_mtimespec.tv_nsec)) xattrs=[\(attrs)] protection=\(protection)"
                entries[child] = Entry(path: child, details: details, hash: data.map(digest),
                    text: unpacked?.0, searchable: unpacked?.1 ?? "")
                if kind == S_IFDIR { walk(current, child, depth + 1) }
            }
        }
        walk(fd, store, 0)
        var final = stat()
        guard allow(store), lstat(root.path, &final) == 0,
              final.st_ino == held.st_ino, final.st_dev == held.st_dev else {
            throw PosterBoardStore.failure("COMPARE store path changed during observation")
        }
        return render(entries: entries, notes: notes, exhausted: exhausted)
    }
    static func render(entries: [String: Entry], notes: [String], exhausted: Bool) -> String {
        var lines = ["COMPARE WITH PLACARD v14 · READ ONLY · store61 · our UUID=\(ours)",
                     "Snapshot bounded 8192 entries / depth20 / 8MiB per file / 96MiB total. Not atomic. No access expansion. Limits/denials mean incomplete, never absent."]
        let prefix = parent + "/"
        let siblings = entries.keys.filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }.sorted()
        lines.append("ALL DESCRIPTOR SIBLINGS (\(siblings.count))")
        for sibling in siblings { lines.append("\(sibling) \(entries[sibling]!.details)") }
        let oursPrefix = prefix + ours + "/"
        let ownFiles = entries.filter { $0.key.hasPrefix(oursPrefix) && $0.value.hash != nil }
        var candidates: [String] = []
        for sibling in siblings where sibling != prefix + ours {
            let files = entries.filter { $0.key.hasPrefix(sibling + "/") }
            let sameAssets = files.filter { key, value in
                let suffix = String(key.dropFirst(sibling.count + 1))
                return !suffix.contains("plist") && value.hash != nil &&
                    (ownFiles[oursPrefix + suffix]?.hash == value.hash || ApprovedAnimeManifest.files[suffix] == value.hash)
            }.count
            let titleMatch = files.values.contains {
                $0.searchable.range(of: "Anime-Squad", options: .caseInsensitive) != nil ||
                $0.searchable.range(of: "Anime Squad", options: .caseInsensitive) != nil
            }
            if sameAssets >= 2 || titleMatch {
                candidates.append(sibling)
                lines.append("CANDIDATE \(sibling) equal non-plist payloads=\(sameAssets) titleMatch=\(titleMatch); provenance UNVERIFIED")
            }
        }
        let selected = [prefix + ours] + candidates
        for descriptor in selected {
            lines.append("FULL TREE \(descriptor)")
            for key in entries.keys.sorted() where key == descriptor || key.hasPrefix(descriptor + "/") {
                let entry = entries[key]!
                lines.append("\(key) \(entry.details) sha256=\(entry.hash ?? "not-read-or-directory")")
                if let text = entry.text { lines.append("FULL STRUCTURED CONTENT \(key)\n\(text)") }
                else if key.hasSuffix("descriptor.identifier") { lines.append("IDENTIFIER \(entry.searchable)") }
            }
        }
        let ids = selected.map { String($0.dropFirst(prefix.count)) }
        lines.append("REFERENCING FILES / OTHER DIRECTORIES UNDER STORE61")
        for key in entries.keys.sorted() {
            let entry = entries[key]!
            let hits = ids.filter { entry.searchable.range(of: $0, options: .caseInsensitive) != nil || key.range(of: $0, options: .caseInsensitive) != nil }
            if !hits.isEmpty {
                lines.append("REFERENCE \(key) UUIDs=\(hits) parent=\(URL(fileURLWithPath: key).deletingLastPathComponent().path)")
                // Full matching structured index/parent content, never unrelated content.
                if !selected.contains(where: { key.hasPrefix($0 + "/") }), let text = entry.text {
                    lines.append("FULL REFERENCING INDEX \(key)\n\(text)")
                }
            }
        }
        lines.append("DIFF")
        if entries[prefix + ours] == nil { lines.append("Our descriptor unread/unlisted. Comparison inconclusive.") }
        if candidates.isEmpty { lines.append("No readable content-match candidate found. Placard copy may be inaccessible/different. Not proof absent.") }
        for candidate in candidates {
            let candidatePrefix = candidate + "/"
            let suffixes = Set(entries.keys.filter { $0.hasPrefix(oursPrefix) }.map { String($0.dropFirst(oursPrefix.count)) })
                .union(entries.keys.filter { $0.hasPrefix(candidatePrefix) }.map { String($0.dropFirst(candidatePrefix.count)) })
            lines.append("DIFF our root vs \(candidate) root metadata equal=\(entries[prefix + ours]?.details == entries[candidate]?.details)")
            var changed = 0
            for suffix in suffixes.sorted() {
                let a = entries[oursPrefix + suffix], b = entries[candidatePrefix + suffix]
                if a?.hash != b?.hash || a?.details != b?.details || a == nil || b == nil {
                    changed += 1
                    lines.append("DIFF \(suffix) ours=\(a == nil ? "MISSING/UNREAD" : a!.details) candidate=\(b == nil ? "MISSING/UNREAD" : b!.details) hashEqual=\(a?.hash != nil && a?.hash == b?.hash) structuredEqual=\(a?.text != nil && a?.text == b?.text)")
                }
            }
            lines.append("DIFF changed entries=\(changed)/\(suffixes.count). mtimes/identity differences are observations, not demonstrated failure causes.")
        }
        lines.append(contentsOf: notes)
        lines.append("COMPARE SNAPSHOT END · incomplete=\(exhausted || !notes.isEmpty) entries=\(entries.count). No gallery visibility inference.")
        return lines.joined(separator: "\n")
    }
}
