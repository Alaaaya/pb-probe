import Foundation

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
        for name in metadata {
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
            let layout = try PosterBoardStore.layout(root)
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
        var identified = false
        for name in metadata {
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
        let layout = try PosterBoardStore.layout(root)
        let collection = layout.extensions.appendingPathComponent(provider)
        guard layout.providers.contains(provider), lease.permits(collection),
              try collection.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw PosterBoardStore.failure("Existing versioned CollectionsPoster marker required.")
        }
        // Metadata alone still requires a real PosterBoard layout, like Mirsa.
        _ = identified
    }
    static func discover(log: @escaping (String) -> Void) throws -> String {
        // Candidate finding deliberately does not impose the chosen identity rule.
        // Diagnose must still be usable when strict validation is the failing step.
        for root in PosterBoardStore.roots {
            log("Scanning \(root)")
            let parent: PosterBoardLease
            do { parent = try PosterBoardLease(path: root, log: log) }
            catch { log(describe(error)); continue }
            let entries: [String]
            do {
                entries = try FileManager.default.contentsOfDirectory(atPath: parent.effectiveURL.path)
                try parent.close()
            } catch { try? parent.close(); log(describe(error)); continue }
            for entry in entries.sorted() where UUID(uuidString: entry) != nil {
                let path = root + "/" + entry
                var detail = ""
                do {
                    let lease = try PosterBoardLease(path: path) { detail += $0 }
                    let store = lease.effectiveURL.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore")
                    let hasMarker = FileManager.default.fileExists(atPath: store.path)
                    var metadataMatch = false
                    for name in metadata {
                        if let d = try? Data(contentsOf: lease.effectiveURL.appendingPathComponent(name)),
                           let obj = try? PropertyListSerialization.propertyList(from: d, format: nil) as? [String: Any],
                           obj["MCMMetadataIdentifier"] as? String == "com.apple.PosterBoard" { metadataMatch = true }
                    }
                    try lease.close()
                    if hasMarker || metadataMatch {
                        log(detail)
                        log("Candidate found \(path), marker=\(hasMarker), metadata=\(metadataMatch)")
                        return path
                    }
                } catch { log("Candidate \(entry) lease/read ERROR \(describe(error))\n\(detail)") }
            }
        }
        throw PosterBoardStore.failure("No PosterBoard candidate found. Paste a known container path to diagnose it directly.")
    }
}
