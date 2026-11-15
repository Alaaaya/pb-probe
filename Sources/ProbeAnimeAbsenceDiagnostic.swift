import Foundation
import Darwin

/// Read-only observation of the exact historical descriptor. Never reconciles
/// its pending marker, calls removal, or treats permission errors as absence.
enum ProbeAnimeAbsenceDiagnostic {
    static func run(path: String, log output: @escaping (String) -> Void, requireAbsence: Bool = false, scope: ProbeAnimeJournalReconcile.Scope? = nil) throws -> String {
        var transcript = ""
        let log: (String) -> Void = { line in transcript += line + "\n"; output(line) }
        let canonical = try PosterBoardStore.canonicalContainer(path)
        guard canonical == path, try ProbeDiagnostics.identifiesPosterBoard(path, log: log) else {
            throw PosterBoardStore.failure("Absence diagnostic requires strict PosterBoard identity.")
        }
        let owner = ProbeOwnedAnimeCleanup.self
        let journalID = scope?.journalID ?? owner.journalID
        let descriptor = scope?.descriptor ?? owner.descriptor
        let relative = scope?.relative ?? owner.relative
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let journal = documents.appendingPathComponent("InstallTests").appendingPathComponent(journalID)
        for url in [documents, journal.deletingLastPathComponent(), journal] {
            let info = try FileManager.default.attributesOfItem(atPath: url.path)
            guard info[.type] as? FileAttributeType == .typeDirectory else {
                throw PosterBoardStore.failure("Absence diagnostic local evidence directory redirected.")
            }
        }
        let pending = journal.appendingPathComponent("pending.json")
        let record = try owner.localRead(pending, limit: 65_536)
        if scope != nil {
            _ = try ProbeAnimeJournalReconcile.Scope(journalID: journalID, record: record, path: path)
        } else { try owner.validateRecord(record, path: path) }
        log("AUDIT ABSENCE · read-only; exact journal validated and preserved; no new backup/removal evidence is created.")
        let lease = try PosterBoardLease(path: path, log: log)
        do {
            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease, rule: .strict)
            // Identical bounded historical grant paths to build17, never expand
            // scope or scan other stores/descriptors. No writes to PosterBoard.
            var paths = Set<String>()
            for file in ApprovedAnimeManifest.files.keys {
                let parts = (relative + "/" + file).split(separator: "/").map(String.init)
                for count in 1...parts.count { paths.insert(parts.prefix(count).joined(separator: "/")) }
            }
            for part in paths.sorted(by: { $0.count < $1.count }) {
                guard lease.grant(part), lease.permits(lease.effectiveURL.appendingPathComponent(part)) else {
                    throw PosterBoardStore.failure("Absence diagnostic existing exact-path access denied/redirected; absence UNKNOWN.")
                }
            }
            let parent = lease.effectiveURL.appendingPathComponent(owner.parentRelative)
            guard lease.permits(parent) else {
                throw PosterBoardStore.failure("Absence diagnostic parent ancestry invalid; absence UNKNOWN.")
            }
            let classification = observe(parent: parent, name: descriptor, log: log)
            if requireAbsence {
                guard classification == "ENOENT_OBSERVED_EXACT_PATH",
                      try ProbeDiagnostics.identifiesPosterBoard(path, log: log),
                      lease.permits(parent) else {
                    throw PosterBoardStore.failure("Exact historical absence not validated; pending preserved.")
                }
                try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease, rule: .strict)
                guard observe(parent: parent, name: descriptor, log: log) == "ENOENT_OBSERVED_EXACT_PATH" else {
                    throw PosterBoardStore.failure("Final absence recheck failed; pending preserved.")
                }
            }
            guard try owner.localRead(pending, limit: 65_536) == record else {
                throw PosterBoardStore.failure("Journal changed externally during read-only observation; no reconciliation performed.")
            }
            try lease.close()
            log("AUDIT ABSENCE COMPLETE · lease closed; pending journal byte-identical; no removal/install/refresh attempted. Copy Log and stop.")
            return transcript
        } catch {
            do { try lease.close() } catch { log("CLEANUP ERROR · \(error.localizedDescription)") }
            throw error
        }
    }

    // Separated for actual macOS syscall fixtures. All errno values are saved
    // immediately after the relevant syscall, before formatting/logging/closing.
    @discardableResult
    static func observe(parent: URL, name: String, log: (String) -> Void) -> String {
        let root = parent.appendingPathComponent(name).path
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW
        let p = open(parent.path, flags)
        let pError = p < 0 ? errno : 0
        log("AUDIT ABSENCE parent=\(parent.path) name=\(name) flags=O_RDONLY|O_DIRECTORY|O_NOFOLLOW")
        result("open(parent)", p, pError, log)
        defer { if p >= 0 { close(p) } }

        var parentHeld = stat()
        var ph: Int32 = -1
        var phError: Int32 = 0
        if p >= 0 {
            ph = fstat(p, &parentHeld)
            phError = ph < 0 ? errno : 0
            metadata("fstat(parentFD=\(p))", ph, phError, parentHeld, log)
        }
        var parentPath = stat()
        let pp = lstat(parent.path, &parentPath)
        let ppError = pp < 0 ? errno : 0
        metadata("lstat(parent)", pp, ppError, parentPath, log)
        let parentMatches = ph == 0 && pp == 0 && same(parentHeld, parentPath) &&
            (parentHeld.st_mode & S_IFMT) == S_IFDIR
        log("AUDIT ABSENCE parentHeldMatchesPath=\(parentMatches)")

        // Reproduce the exact build17 failing call before other root observations.
        var relative: Int32 = -1
        var relativeError: Int32 = 0
        if p >= 0 {
            relative = openat(p, name, flags)
            relativeError = relative < 0 ? errno : 0
            result("openat(parentFD=\(p), exactName)", relative, relativeError, log)
        } else { log("AUDIT ABSENCE openat skipped; no valid parentFD") }
        defer { if relative >= 0 { close(relative) } }
        var relativeHeld = stat()
        var rh: Int32 = -1
        if relative >= 0 {
            rh = fstat(relative, &relativeHeld)
            let e = rh < 0 ? errno : 0
            metadata("fstat(relativeRootFD)", rh, e, relativeHeld, log)
        }
        var absolutePath = stat()
        let ap = lstat(root, &absolutePath)
        let apError = ap < 0 ? errno : 0
        metadata("lstat(exactRoot)", ap, apError, absolutePath, log)
        var relativePath = stat()
        var rp: Int32 = -1
        var rpError: Int32 = 0
        if p >= 0 {
            rp = fstatat(p, name, &relativePath, AT_SYMLINK_NOFOLLOW)
            rpError = rp < 0 ? errno : 0
            metadata("fstatat(parentFD, exactName, AT_SYMLINK_NOFOLLOW)", rp, rpError, relativePath, log)
        }
        let absolute = open(root, flags)
        let absoluteError = absolute < 0 ? errno : 0
        result("open(exactAbsoluteRoot)", absolute, absoluteError, log)
        defer { if absolute >= 0 { close(absolute) } }
        var absoluteHeld = stat()
        var ah: Int32 = -1
        if absolute >= 0 {
            ah = fstat(absolute, &absoluteHeld)
            let e = ah < 0 ? errno : 0
            metadata("fstat(absoluteRootFD)", ah, e, absoluteHeld, log)
        }
        // Recheck parent path and exact entry after observation. This is a
        // point-in-time diagnostic, not an atomic absence/reconciliation grant.
        var finalParent = stat()
        let fp = lstat(parent.path, &finalParent)
        let fpError = fp < 0 ? errno : 0
        metadata("lstat(parent, final)", fp, fpError, finalParent, log)
        var finalRoot = stat()
        var fr: Int32 = -1
        var frError: Int32 = 0
        if p >= 0 {
            fr = fstatat(p, name, &finalRoot, AT_SYMLINK_NOFOLLOW)
            frError = fr < 0 ? errno : 0
            metadata("fstatat(exactName, final)", fr, frError, finalRoot, log)
        }
        let stableParent = parentMatches && fp == 0 && same(parentHeld, finalParent)
        let observedAbsent = stableParent && relative < 0 && relativeError == ENOENT &&
            ap < 0 && apError == ENOENT && rp < 0 && rpError == ENOENT &&
            absolute < 0 && absoluteError == ENOENT && fr < 0 && frError == ENOENT
        let present = stableParent && rh == 0 && ah == 0 && ap == 0 && rp == 0 && fr == 0 &&
            (absoluteHeld.st_mode & S_IFMT) == S_IFDIR && same(relativeHeld, absoluteHeld) &&
            same(absoluteHeld, absolutePath) && same(absolutePath, relativePath) && same(relativePath, finalRoot)
        let classification = observedAbsent ? "ENOENT_OBSERVED_EXACT_PATH" : (present ? "PRESENT_MATCHING_DIRECTORY" : "INCONCLUSIVE_OR_PATH_ERROR")
        log("AUDIT ABSENCE CLASSIFICATION \(classification) · observation only, not cleanup success or authorization to clear pending. Permission errors never mean absent.")
        return classification
    }
    static func same(_ a: stat, _ b: stat) -> Bool {
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && (a.st_mode & S_IFMT) == (b.st_mode & S_IFMT)
    }
    static func result(_ operation: String, _ value: Int32, _ error: Int32, _ log: (String) -> Void) {
        log("AUDIT ABSENCE \(operation) rc=\(value) errno=\(error) \(error == 0 ? "OK" : String(cString: strerror(error)))")
    }
    static func metadata(_ operation: String, _ value: Int32, _ error: Int32, _ st: stat, _ log: (String) -> Void) {
        result(operation, value, error, log)
        if value == 0 { log("AUDIT ABSENCE \(operation) dev=\(st.st_dev) ino=\(st.st_ino) mode=\(st.st_mode) uid=\(st.st_uid) gid=\(st.st_gid)") }
    }
}
