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
    struct Limits {
        var seconds: Double = 30
        var grants = 128 // At most 128 extra retained handles, plus fixed identity/base lease.
        var denials = 2
        var entries = 512
        var names = 256
        var siblings = 12
        var candidates = 2
        var depth = 20
        var bytes = 33_554_432
    }
    static func run(path: String, log: @escaping (String) -> Void) throws -> String {
        let lease = try PosterBoardLease(path: path, log: log)
        var report: String
        do {
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease, rule: .strict)
            report = try collect(base: lease.effectiveURL, allow: { relative in
                lease.grant(relative) && lease.permits(lease.effectiveURL.appendingPathComponent(relative))
            }, progress: log)
        } catch {
            report = render(entries: [:], notes: ["ERROR before collection: \(error.localizedDescription)"], exhausted: true)
        }
        // Preserve even partial observations if cleanup itself fails. Never claim closure on failure.
        do {
            try lease.close()
            report += "\nAUDIT COMPARE COMPLETE · lease closed; no writes; device/gallery unverified."
        } catch {
            report += "\nCLEANUP ERROR · \(error.localizedDescription) · incomplete=true; closure NOT verified."
        }
        log("COMPARE TERMINAL · returning evidence after cleanup attempt")
        return report
    }
    static func collect(base: URL, allow: (String) -> Bool, limits: Limits = Limits(),
                        now: () -> Double = { ProcessInfo.processInfo.systemUptime },
                        progress: (String) -> Void = { _ in }) throws -> String {
        var entries: [String: Entry] = [:]
        var notes: [String] = []
        var count = 0
        var total = 0
        var exhausted = false
        var attempts = 0
        var denials = 0
        var granted = Set<String>()
        var rejected = Set<String>()
        let started = now()
        func available() -> Bool {
            if exhausted { return false }
            if now() - started >= limits.seconds || count >= limits.entries ||
               denials >= limits.denials || total >= limits.bytes {
                notes.append("LIMIT cooperative time/entry/denial/read budget")
                exhausted = true
                return false
            }
            return true
        }
        func permit(_ relative: String) -> Bool {
            guard available() else { return false }
            if granted.contains(relative) { return true }
            if rejected.contains(relative) { return false }
            guard attempts < limits.grants else {
                notes.append("LIMIT total grant attempts=\(attempts); retained handles bounded")
                exhausted = true; return false
            }
            attempts += 1
            let ok = allow(relative)
            if ok { granted.insert(relative) } else { denials += 1; rejected.insert(relative) }
            progress("COMPARE COUNT grants=\(attempts) denied=\(denials) entries=\(entries.count) bytes=\(total)")
            // A single native call cannot be preempted. Check again before any more work.
            let remaining = available()
            return ok && remaining
        }
        func finish() -> String {
            notes.append("SCOPE CollectionsPoster/descriptors only; external index/reference search deliberately NOT performed")
            notes.append("COUNTS grantAttempts=\(attempts) denials=\(denials) observedEntries=\(entries.count) bytes=\(total)")
            return render(entries: entries, notes: notes, exhausted: exhausted)
        }
        progress("COMPARE PHASE ancestors · own pinned descriptor FIRST")
        // Only exact necessary ancestors. Never enumerate store61 or other providers.
        let parts = parent.split(separator: "/").map(String.init)
        for i in 1...parts.count {
            guard permit(parts.prefix(i).joined(separator: "/")) else {
                notes.append("DENIED/REDIRECTED ancestor; partial snapshot")
                return finish()
            }
        }
        let root = base.appendingPathComponent(parent)
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { notes.append("DENIED descriptors open errno=\(errno)"); return finish() }
        defer { close(fd) }
        var held = stat()
        guard fstat(fd, &held) == 0 else { notes.append("DENIED descriptors fstat"); return finish() }
        enum Phase { case own, metadata, candidate }
        let metadataNames: Set<String> = ["com.apple.posterkit.provider.descriptor.identifier",
            "com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist", "providerInfo.plist", "Wallpaper.plist"]
        var phase = Phase.own
        var candidateNames = Set<String>()
        var siblingCount = 0
        func walk(_ directory: Int32, _ relative: String, _ depth: Int) {
            guard available() else { return }
            guard depth <= limits.depth else { notes.append("LIMIT depth"); exhausted = true; return }
            let copied = dup(directory)
            guard copied >= 0 else { notes.append("DENIED dup \(relative)"); return }
            guard let stream = fdopendir(copied) else { close(copied); notes.append("DENIED list \(relative)"); return }
            defer { closedir(stream) }
            rewinddir(stream)
            var names: [String] = []
            errno = 0
            // Do not enumerate any sibling before opening our exact pinned UUID.
            if relative == parent && phase == .own { names = [ours] }
            while !(relative == parent && phase == .own), available(), let item = readdir(stream) {
                let name = withUnsafePointer(to: &item.pointee.d_name) {
                    $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
                }
                if name != "." && name != ".." {
                    guard names.count < limits.names else { notes.append("LIMIT shallow names"); exhausted = true; break }
                    names.append(name)
                }
                errno = 0
            }
            if errno != 0 { notes.append("DENIED readdir \(relative) errno=\(errno)") }
            for name in names.sorted() {
                guard available() else { return }
                if relative == parent {
                    guard UUID(uuidString: name) != nil else { continue }
                    switch phase {
                    case .own: guard name == ours else { continue }
                    case .metadata:
                        guard name != ours else { continue }
                        guard siblingCount < limits.siblings else { notes.append("LIMIT metadata sibling selection"); return }
                        siblingCount += 1
                    case .candidate: guard candidateNames.contains(name) else { continue }
                    }
                } else if phase == .metadata {
                    // Root metadata only. No versions/assets or arbitrary subdirectories.
                    guard depth == 1, metadataNames.contains(name) else { continue }
                }
                count += 1
                let child = relative + "/" + name
                guard !name.contains("/"), permit(child) else { notes.append("DENIED/REDIRECTED \(child)"); continue }
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
                    if info.st_size >= 0 && info.st_size <= (phase == .metadata ? 65_536 : 8_388_608) && total + Int(info.st_size) <= limits.bytes {
                        var bytes = Data()
                        var buffer = [UInt8](repeating: 0, count: 65536)
                        var failed = false
                        while available(), bytes.count <= 8_388_608 {
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
                    } else { notes.append("LIMIT payload unread \(child) bytes=\(info.st_size)") }
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
                if available(), fstatat(directory, name, &check, AT_SYMLINK_NOFOLLOW) == 0,
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
        // Own full tree before granting any sibling UUID.
        walk(fd, parent, 0)
        phase = .metadata
        progress("COMPARE PHASE bounded UUID root metadata · no unrelated provider/version traversal")
        walk(fd, parent, 0)
        for key in entries.keys.sorted() {
            guard available() else { break }
            let entry = entries[key]!
            let prefix = parent + "/"
            guard key.hasPrefix(prefix) else { continue }
            let components = key.dropFirst(prefix.count).split(separator: "/")
            guard components.count == 2, components[0] != Substring(ours) else { continue }
            let title = entry.searchable.range(of: "Anime-Squad", options: .caseInsensitive) != nil ||
                        entry.searchable.range(of: "Anime Squad", options: .caseInsensitive) != nil
            let identifierMatch = components[1] == "com.apple.posterkit.provider.descriptor.identifier" &&
                entry.hash != nil && entry.hash == ApprovedAnimeManifest.files[String(components[1])]
            if title || identifierMatch {
                if candidateNames.count < limits.candidates { candidateNames.insert(String(components[0])) }
                else if !candidateNames.contains(String(components[0])) { notes.append("LIMIT candidate selection") }
            }
        }
        phase = .candidate
        progress("COMPARE PHASE selected candidate trees=\(candidateNames.count)")
        if !candidateNames.isEmpty { walk(fd, parent, 0) }
        var final = stat()
        if !available() || !permit(parent) || lstat(root.path, &final) != 0 ||
           final.st_ino != held.st_ino || final.st_dev != held.st_dev {
            notes.append("FINAL REVALIDATION FAILED/NOT COMPLETED · partial evidence retained")
        }
        return finish()
    }
    static func render(entries: [String: Entry], notes: [String], exhausted: Bool) -> String {
        var lines = ["COMPARE WITH PLACARD v15 · READ ONLY · CollectionsPoster only · our UUID=\(ours)",
                     "Snapshot defaults 30s cooperative / 128 grant attempts / 2 denials / 512 entries / 256 names per directory / 12 metadata siblings / 2 candidate trees / depth20 / 8MiB per file / 32MiB total. Native calls not preemptible. No access expansion. Limits mean incomplete, never absent."]
        let prefix = parent + "/"
        let siblings = entries.keys.filter { $0.hasPrefix(prefix) && !$0.dropFirst(prefix.count).contains("/") }.sorted()
        lines.append("BOUNDED OBSERVED DESCRIPTOR SIBLINGS (\(siblings.count))")
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
            let identifierMatch = files.contains { key, value in
                key.hasSuffix("/com.apple.posterkit.provider.descriptor.identifier") && value.hash != nil &&
                    value.hash == ApprovedAnimeManifest.files["com.apple.posterkit.provider.descriptor.identifier"]
            }
            if sameAssets >= 2 || titleMatch || identifierMatch {
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
        lines.append("REFERENCES IN SELECTED SCOPE ONLY · external indexes NOT searched")
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
