import Foundation

@_silgen_name("mirsa_pb_candidates_copy_json")
private func copyCandidateJSON() -> UnsafeMutablePointer<CChar>?
@_silgen_name("mirsa_pb_target_identity_json")
private func copyTargetIdentity(_ path: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>?
@_silgen_name("mirsa_pb_has_own_group")
private func hasOwnGroup(_ log: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32
@_silgen_name("mirsa_pb_access_free_string")
private func freeProbeString(_ value: UnsafeMutablePointer<CChar>)


enum IdentityRule: String, CaseIterable {
    case strict = "Strict"
    case metadataOrMarkers = "Metadata or markers"
}

enum ProbeDiagnostics {
    static let provider = "com.apple.WallpaperKit.CollectionsPoster"
    static let metadata = [".com.apple.mobile_container_manager.metadata.plist",
                           "com.apple.mobile_container_manager.metadata.plist"]

    static func names(_ url: URL, label: String, log: (String) -> Void) {
        do {
            log("\(label) names = \(try FileManager.default.contentsOfDirectory(atPath: url.path).sorted())")
        } catch { log("\(label) listing ERROR \(describe(error))") }
    }
    static func describe(_ error: Error) -> String {
        let e = error as NSError
        return "\(e.domain) code=\(e.code) \(e.localizedDescription)"
    }
    static func inspect(_ lease: PosterBoardLease, log: (String) -> Void) {
        let root = lease.effectiveURL, fm = FileManager.default
        log("lease target = \(lease.targetURL.path)")
        log("effective path = \(root.path)")
        log("resolved effective = \(root.resolvingSymlinksInPath().path)")
        log("resolved target = \(lease.targetURL.resolvingSymlinksInPath().path)")
        do { log("effective symlink destination = \(try fm.destinationOfSymbolicLink(atPath: root.path))") }
        catch { log("effective symlink lookup = \(describe(error))") }
        log("lease exact-path validation = \(lease.permits(root))")
        lease.grantLayout()
        log("container identity xattr = \(lease.identityAttribute() ?? "<unreadable>")")
        for name in metadata {
            lease.grant(name)
            let file = root.appendingPathComponent(name)
            log("\(name) exists=\(fm.fileExists(atPath: file.path)) readable=\(fm.isReadableFile(atPath: file.path)) unredirected=\(lease.permits(file))")
            do {
                let data = try Data(contentsOf: file)
                let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
                log("\(name) MCMMetadataIdentifier = \(info?["MCMMetadataIdentifier"] ?? "<missing>")")
            } catch { log("\(name) read/parse ERROR \(describe(error))") }
        }
        names(root, label: "Top-level", log: log)
        names(root.appendingPathComponent("Library/Application Support"), label: "Library/Application Support", log: log)
        for marker in ["Library/Application Support/PRBPosterExtensionDataStore",
                       "Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist"] {
            let file = root.appendingPathComponent(marker)
            log("marker \(marker) exists=\(fm.fileExists(atPath: file.path)) unredirected=\(lease.permits(file))")
        }
        do {
            let layout = try PosterBoardStore.layout(root, lease: lease)
            log("version=\(layout.version) providers=\(layout.providers.sorted())")
        } catch { log("Layout ERROR \(describe(error))") }
        for rule in IdentityRule.allCases {
            do {
                try PosterBoardStore.validateIdentity(root, lease: lease, rule: rule)
                log("identity \(rule.rawValue) = PASS")
            } catch { log("identity \(rule.rawValue) = FAIL \(describe(error))") }
        }
    }
    static func validate(_ root: URL, lease: PosterBoardLease?) throws {
        guard let lease, lease.permits(root),
              (try? PosterBoardStore.canonicalContainer(lease.targetURL.path)) != nil else {
            throw PosterBoardStore.failure("Markers require an active exact canonical-container lease.")
        }
        // A readable contradictory or malformed metadata file is NEVER overridden by markers.
        lease.grantLayout()
        if let attribute = lease.identityAttribute(), attribute != "com.apple.PosterBoard" {
            throw PosterBoardStore.failure("Container identity attribute contradicts com.apple.PosterBoard.")
        }
        var identified = false
        for name in metadata {
            lease.grant(name)
            let file = root.appendingPathComponent(name)
            guard lease.permits(file) else { throw PosterBoardStore.failure("Redirected metadata rejected.") }
            if let data = try? Data(contentsOf: file) {
                guard let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      info["MCMMetadataIdentifier"] as? String == "com.apple.PosterBoard" else {
                    throw PosterBoardStore.failure("Readable metadata does not identify com.apple.PosterBoard.")
                }
                identified = true
            }
        }
        let store = root.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore")
        guard lease.permits(store) else { throw PosterBoardStore.failure("Redirected PosterBoard store.") }
        let layout = try PosterBoardStore.layout(root, lease: lease)
        let collection = layout.extensions.appendingPathComponent(provider)
        guard layout.providers.contains(provider), lease.permits(collection),
              try collection.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw PosterBoardStore.failure("Existing versioned CollectionsPoster marker required.")
        }
        // Metadata alone still requires a real PosterBoard layout, like Mirsa.
        _ = identified
    }
    static func identifiesPosterBoard(_ path: String, log: (String) -> Void) throws -> Bool {
        guard let pointer = path.withCString({ copyTargetIdentity($0) }) else {
            throw PosterBoardStore.failure("Metadata identity report missing.")
        }
        let text = String(cString: pointer)
        freeProbeString(pointer)
        log("IDENTITY metadata result \(text)")
        guard let bytes = text.data(using: .utf8),
              let identity = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { return false }
        if identity["restoreFailure"] as? Bool == true {
            throw PosterBoardStore.failure("Own Caches restore failed. Stop; backup retained.")
        }
        return identity["matched"] as? Bool == true
    }
    static func discover(log: @escaping (String) -> Void) throws -> String {
        log("DISCOVERY BEFORE own-group query")
        var details: UnsafeMutablePointer<CChar>?
        let groupCount = hasOwnGroup(&details)
        if let details { log(String(cString: details)); freeProbeString(details) }
        log("DISCOVERY AFTER own-group query; count=\(groupCount)")
        guard groupCount > 0 else {
            throw PosterBoardStore.failure("placard-style needs one usable own app group. See the entitlement acquisition, embedded group values and per-group containerURL results above. Cause is not established. get-task-allow is NOT required.")
        }
        // Listing a data-container parent may be denied even when exact-path
        // extensions work. Resolve UUID candidates on our own data volume first.
        log("DISCOVERY BEFORE copyCandidateJSON; synchronous calls cannot be forcibly cancelled safely")
        let deadline = ProcessInfo.processInfo.systemUptime + 20
        var attempts = 0
        if let pointer = copyCandidateJSON() {
            log("DISCOVERY AFTER copyCandidateJSON")
            let json = String(cString: pointer)
            freeProbeString(pointer)
            if let data = json.data(using: .utf8),
               let report = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                log("placard-style inode discovery visited=\(report["visitedInodes"] ?? "?") seconds=\(report["seconds"] ?? "?") limited=\(report["timeLimited"] ?? "?") UUIDs=\(report["UUIDContainersSeen"] ?? "?")")
                if let error = report["error"] { log("discovery ERROR \(error)") }
                log("DISCOVERY aggregate unknown xattr=\(report["unknownIdentityCount"] ?? "?") other identity=\(report["otherIdentityCount"] ?? "?"); these receive NO access grants")
                log("DISCOVERY scan start=\(report["startInode"] ?? "?") next=\(report["nextInode"] ?? "?") complete=\(report["scanComplete"] ?? "?"); next Diagnose resumes if time-limited")
                let exact = report["matched"] as? [String] ?? []
                let hints = report["hinted"] as? [String] ?? []
                let candidates = Array(Set(exact + hints)).sorted()
                log("DISCOVERY exact xattr matches=\(exact.count) PosterBoard-specific path hints=\(hints.count); verify exact metadata only, no arbitrary candidate roots")
                for raw in candidates {
                    guard attempts < 8, ProcessInfo.processInfo.systemUptime < deadline else {
                        log("DISCOVERY targeted metadata budget reached; no further access calls")
                        break
                    }
                    attempts += 1
                    let path = try PosterBoardStore.canonicalContainer(raw)
                    log("IDENTITY target \(attempts) · \(path) · reason=\(exact.contains(raw) ? "exact PosterBoard xattr" : "PosterBoard-specific path hint")")
                    if try identifiesPosterBoard(path, log: log) {
                        log("PosterBoard VERIFIED by MCMMetadataIdentifier=com.apple.PosterBoard · \(path)")
                        return path
                    }
                }
            }
        }
        log("DISCOVERY FINISHED · no metadata-verified PosterBoard in this bounded pass. Unknown containers were NOT granted access. If scan was time-limited, Diagnose resumes scanning. No writes performed.")
        throw PosterBoardStore.failure("No PosterBoard candidate identified. Paste a known canonical container path to diagnose directly.")
    }
}
