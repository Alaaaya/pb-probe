import Foundation
import Darwin
import CryptoKit

/// Bounded read-only observation. No directory recursion or payload dumping.
enum ProbeGalleryAudit {
    static let target = "BE2EE206-9948-4F2B-BD3E-C02042EDBC5D"
    static let original = "00B33CEB-3768-4682-81AD-0384CDA80B22"
    static let markers = [target, original, "7400"]
    static let metadata = [
        "com.apple.posterkit.provider.descriptor.identifier",
        "com.apple.posterkit.provider.contents.userInfo",
        "com.apple.posterkit.provider.descriptor.role",
        "com.apple.posterkit.provider.contents.suggestionMetadata",
        "Wallpaper.plist"
    ]
    static func references(_ data: Data) -> [Bool] {
        // Decode structured binary plists without printing their private contents.
        let structured = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil))
            ?? (try? JSONSerialization.jsonObject(with: data))
        let text = structured.map { String(describing: $0) } ?? String(decoding: data, as: UTF8.self)
        return markers.map { text.range(of: $0, options: .caseInsensitive) != nil }
    }
    static func run(path: String, log: @escaping (String) -> Void) throws {
        let lease = try PosterBoardLease(path: path, log: log)
        do {
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease, rule: .strict)
            let parent = try ProbeInstallTest.destination(lease: lease)
            log("AUDIT selected existing provider/store=\(parent); newest existing provider is not proof of active gallery version")
            let root = String(parent.prefix(parent.count - ("/Extensions/" + ProbeInstallTest.provider + "/descriptors").count))
            let fm = FileManager.default
            let names = try fm.contentsOfDirectory(atPath: lease.effectiveURL.appendingPathComponent(parent).path)
            guard names.count <= 256 else { throw PosterBoardStore.failure("AUDIT stopped: more than 256 directory entries") }
            let siblings = names.filter { UUID(uuidString: $0) != nil && $0.caseInsensitiveCompare(target) != .orderedSame }.sorted()
            log("AUDIT target directory listed=\(names.contains { $0.caseInsensitiveCompare(target) == .orderedSame }); UUID siblings=\(siblings.count)")
            for (label, relative) in [("provider", parent), ("target", parent + "/" + target)] {
                observe(relative, label: label, lease: lease, log: log)
            }
            if let sibling = siblings.first {
                // Intentionally do not publish sibling UUID or claim visibility.
                log("AUDIT sibling chosen deterministically; visibility UNKNOWN")
                observe(parent + "/" + sibling, label: "sibling", lease: lease, log: log)
            } else { log("AUDIT no sibling available") }
            let index = root + "/PRPosterRoleLockScreen-gallery-index.json"
            read(index, label: "gallery-index", limit: 2_000_000, lease: lease, log: log)
            try lease.close()
            log("AUDIT COMPLETE · read-only observation and lease close completed. Index membership is not visibility or cause proof. ACL not inspected; no payloads/preferences/registration/reset touched.")
        } catch {
            do { try lease.close() } catch { log("CLEANUP ERROR · \(error.localizedDescription)") }
            throw error
        }
    }
    static func observe(_ relative: String, label: String, lease: PosterBoardLease, log: (String) -> Void) {
        attrs(relative, label: label, lease: lease, log: log)
        guard label != "provider" else { return }
        // Only fixed metadata names, never enumerate descriptor descendants.
        for file in metadata {
            let child = relative + "/" + file
            attrs(child, label: label + "/" + file, lease: lease, log: log)
            read(child, label: label + "/" + file, limit: 262_144, lease: lease, log: log)
        }
    }
    static func attrs(_ relative: String, label: String, lease: PosterBoardLease, log: (String) -> Void) {
        let url = lease.effectiveURL.appendingPathComponent(relative)
        guard lease.grant(relative), lease.permits(url) else { log("AUDIT \(label) attrs denied/redirected"); return }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { log("AUDIT \(label) lstat errno=\(errno)"); return }
        guard (info.st_mode & S_IFMT) != S_IFLNK else { log("AUDIT \(label) symlink rejected"); return }
        let protection = (try? FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey]).map { String(describing: $0) } ?? "unavailable"
        log("AUDIT \(label) uid=\(info.st_uid) gid=\(info.st_gid) mode=\(String(info.st_mode, radix: 8)) flags=\(info.st_flags) bytes=\(info.st_size) protection=\(protection)")
        // Names are represented by digests; values and user attributes never dumped.
        let count = listxattr(url.path, nil, 0, XATTR_NOFOLLOW)
        guard count >= 0, count <= 8192 else { log("AUDIT \(label) xattr names unavailable/oversized errno=\(errno)"); return }
        var bytes = [CChar](repeating: 0, count: max(1, count))
        let got = listxattr(url.path, &bytes, bytes.count, XATTR_NOFOLLOW)
        guard got >= 0, got <= count else { log("AUDIT \(label) xattr listing changed/unavailable"); return }
        let data = Data(bytes.prefix(got).map { UInt8(bitPattern: $0) })
        log("AUDIT \(label) xattr-name-list bytes=\(got) sha256=\(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()); values not read")
    }
    static func read(_ relative: String, label: String, limit: Int, lease: PosterBoardLease, log: (String) -> Void) {
        let url = lease.effectiveURL.appendingPathComponent(relative)
        guard lease.grant(relative), lease.permits(url) else { log("AUDIT \(label) read denied/redirected"); return }
        // O_NOFOLLOW and a hard read cap also cover replacements after permits().
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { log("AUDIT \(label) open errno=\(errno)"); return }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= limit else { log("AUDIT \(label) nonregular/oversized; skipped"); return }
        var bytes = [UInt8](repeating: 0, count: limit + 1)
        var total = 0
        while total < bytes.count {
            let got = bytes.withUnsafeMutableBytes { raw in
                Darwin.read(fd, raw.baseAddress!.advanced(by: total), raw.count - total)
            }
            if got == 0 { break }
            if got < 0 { log("AUDIT \(label) read errno=\(errno)"); return }
            total += got
        }
        guard total <= limit else { log("AUDIT \(label) grew beyond cap; skipped"); return }
        let data = Data(bytes.prefix(total))
        let matches = references(data)
        log("AUDIT \(label) bytes=\(total) sha256=\(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()) refs[target,original,7400]=\(matches). Substring references only; not proof of index membership/visibility.")
    }
}
