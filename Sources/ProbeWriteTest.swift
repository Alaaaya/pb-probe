import Foundation
import Darwin

/// A temporary access test, never a wallpaper descriptor or preferences edit.
enum ProbeWriteTest {
    static func run(path: String, log: @escaping (String) -> Void) throws {
        guard try ProbeDiagnostics.identifiesPosterBoard(path, log: log) else {
            throw PosterBoardStore.failure("Strict metadata identity required before access test.")
        }
        let lease = try PosterBoardLease(path: path, log: log)
        do {
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease, rule: .strict)
            // Access proof needs only the already-validated store directory.
            // Do not enumerate versions, providers or descriptor directories.
            let relative = "Library/Application Support/PRBPosterExtensionDataStore"
            let parent = lease.effectiveURL.appendingPathComponent(relative)
            let name = ".pb-probe-access-" + UUID().uuidString
            let target = parent.appendingPathComponent(name)
            guard lease.grant(relative), lease.grant(relative + "/" + name),
                  lease.permits(parent), lease.permits(target),
                  try parent.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
                throw PosterBoardStore.failure("Exact test path access unavailable. Nothing written.")
            }
            let payload = Data(("PB PROBE ACCESS ONLY " + UUID().uuidString).utf8)
            let journal = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("AccessTests").appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
            try payload.write(to: journal.appendingPathComponent("sentinel-backup.bin"), options: .atomic)
            let record: [String: Any] = ["container": path, "relative": relative + "/" + name,
                "purpose": "temporary write/readback/remove only", "existingFilesModified": false]
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys])
                .write(to: journal.appendingPathComponent("pending.json"), options: .atomic)
            // Revalidate immediately before first device write. Any failure closes the lease.
            guard try ProbeDiagnostics.identifiesPosterBoard(path, log: log),
                  lease.permits(target) else {
                throw PosterBoardStore.failure("Identity/path changed before write. Nothing written.")
            }
            log("TEST BEFORE exclusive sentinel create; exact existing datastore root; journal=\(journal.lastPathComponent)")
            try exclusiveRoundTrip(target, payload: payload, log: log)
            try Data("PASS write/readback/cleanup; no wallpaper installed".utf8)
                .write(to: journal.appendingPathComponent("complete.txt"), options: .atomic)
            try lease.close()
            log("ACCESS TEST COMPLETE · write/readback/removal verified. No wallpaper installed or registered. Send this log before any next step.")
        } catch {
            do { try lease.close() } catch { log("CLEANUP ERROR · \(error.localizedDescription)") }
            throw error
        }
    }

    /// O_EXCL prevents replacement, O_NOFOLLOW rejects symlinks. Cleanup only
    /// unlinks the inode created by this call; no recursive removal is used.
    static func exclusiveRoundTrip(_ target: URL, payload: Data, log: (String) -> Void) throws {
        func fail(_ stage: String) -> NSError {
            NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                    userInfo: [NSLocalizedDescriptionKey: "\(stage) errno=\(errno)"])
        }
        let fd = open(target.path, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw fail("Exclusive test create failed") }
        defer { close(fd) }
        var owned = stat()
        guard fstat(fd, &owned) == 0 else {
            // Cannot prove ownership without fstat. Preserve evidence, never guess.
            throw fail("Test fstat failed; sentinel may remain, see pending journal")
        }
        var operationError: Error?
        do {
            try payload.withUnsafeBytes { bytes in
                var offset = 0
                while offset < bytes.count {
                    let count = write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw fail("Test write failed") }
                    offset += count
                }
            }
            guard fsync(fd) == 0, lseek(fd, 0, SEEK_SET) == 0 else { throw fail("Test sync/seek failed") }
            var result = Data(count: payload.count + 1)
            let count = result.withUnsafeMutableBytes { read(fd, $0.baseAddress!, $0.count) }
            guard count == payload.count else { throw PosterBoardStore.failure("Test readback length mismatch.") }
            result.count = count
            guard result == payload else { throw PosterBoardStore.failure("Test readback bytes mismatch.") }
            log("TEST readback exact bytes PASS · \(count)")
        } catch { operationError = error }
        var current = stat()
        guard lstat(target.path, &current) == 0,
              current.st_dev == owned.st_dev, current.st_ino == owned.st_ino,
              (current.st_mode & S_IFMT) == S_IFREG else {
            throw PosterBoardStore.failure("Test cleanup stopped: path ownership changed. No foreign file removed. See pending journal.")
        }
        guard unlink(target.path) == 0 else { throw fail("Test cleanup failed; see pending journal") }
        errno = 0
        guard lstat(target.path, &current) == -1, errno == ENOENT else {
            throw PosterBoardStore.failure("Test removal could not be verified.")
        }
        log("TEST cleanup verified · only own sentinel removed")
        if let operationError { throw operationError }
    }
}
