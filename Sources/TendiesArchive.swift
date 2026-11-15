import Foundation
import ZIPFoundation

final class TendiesArchive {
    /// Validate before either import or flash invokes the native ZIP extractor.
    func validateArchive(_ url: URL) throws {
        try validateEntries(Archive(url: url, accessMode: .read))
    }

    private func validateEntries(_ archive: Archive) throws {
        var total: UInt64 = 0, count = 0
        var paths = Set<String>()
        for entry in archive {
            count += 1
            let size = UInt64(entry.uncompressedSize)
            guard size <= 536_870_912, total <= 536_870_912 - size else {
                throw PosterBoardStore.failure("Oversized wallpaper archive.")
            }
            total += size
            let canonicalEntry = entry.type == .directory && entry.path.hasSuffix("/")
                ? String(entry.path.dropLast()) : entry.path
            let parts = canonicalEntry.split(separator: "/", omittingEmptySubsequences: false)
            guard !canonicalEntry.isEmpty, !parts.contains(""), !parts.contains(where: { $0.contains(":") }),
                  !entry.path.isEmpty, !entry.path.hasPrefix("/"), !entry.path.contains("\\"),
                  !entry.path.contains("\0"), !parts.contains(".."), !parts.contains("."),
                  entry.type == .file || entry.type == .directory,
                  paths.insert(canonicalEntry.precomposedStringWithCanonicalMapping.lowercased()).inserted, count <= 8192 else {
                throw PosterBoardStore.failure("Unsafe wallpaper archive.")
            }
        }
        guard count > 0 else { throw PosterBoardStore.failure("Empty wallpaper archive.") }
    }

    /// The validated parser also extracts, so native parser disagreements cannot
    /// turn a checked pathname into an unchecked filesystem write.
    func extractValidatedArchive(_ url: URL, to root: URL) throws {
        let archive = try Archive(url: url, accessMode: .read)
        try validateEntries(archive)
        let fm = FileManager.default
        let rootInfo = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootInfo.isDirectory == true, rootInfo.isSymbolicLink != true,
              try fm.contentsOfDirectory(atPath: root.path).isEmpty else {
            throw PosterBoardStore.failure("Extraction requires a fresh empty private directory.")
        }
        var actualTotal: UInt64 = 0
        var directories: [(Entry, URL)] = []
        for entry in archive {
            let parts = entry.path.split(separator: "/")
            let hiddenJunk = parts.contains { part in
                part == "__MACOSX" || (part.hasPrefix(".") &&
                    part != ".com.apple.posterkit.provider.contents.configurableOptions.plist")
            }
            if hiddenJunk { continue }
            let target = root.appendingPathComponent(entry.path)
            guard target.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") else {
                throw PosterBoardStore.failure("Archive destination escaped its private root.")
            }
            if entry.type == .directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                directories.append((entry, target))
                continue
            }
            // First bounded streaming pass retains the existing runtime size/CRC
            // protections. The public URL extractor then applies ZIP permissions
            // and mtime using the pinned library, not private ZIP internals.
            var actualSize: UInt64 = 0
            let checksum = try archive.extract(entry) { chunk in
                let next = UInt64(chunk.count)
                guard actualSize <= UInt64(entry.uncompressedSize),
                      next <= UInt64(entry.uncompressedSize) - actualSize,
                      actualTotal <= 536_870_912, next <= 536_870_912 - actualTotal else {
                    throw PosterBoardStore.failure("Oversized wallpaper data.")
                }
                actualSize += next
                actualTotal += next
            }
            guard actualSize == UInt64(entry.uncompressedSize), checksum == entry.checksum else {
                throw PosterBoardStore.failure("Wallpaper checksum mismatch.")
            }
            let writtenCRC = try archive.extract(entry, to: target)
            let written = try target.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey])
            guard writtenCRC == entry.checksum, written.isRegularFile == true,
                  written.isSymbolicLink != true, written.fileSize == Int(actualSize) else {
                throw PosterBoardStore.failure("Extracted wallpaper readback mismatch.")
            }
        }
        // Defer explicit directory attributes until children exist, deepest first,
        // so child creation cannot change archived directory dates.
        for (entry, target) in directories.sorted(by: { $0.1.pathComponents.count > $1.1.pathComponents.count }) {
            guard try archive.extract(entry, to: target) == entry.checksum else {
                throw PosterBoardStore.failure("Directory checksum mismatch.")
            }
        }
    }

    /// Prepare an isolated new descriptor without changing the imported archive.
    /// Numeric wallpaper/provider identities are deliberately preserved together;
    /// only references to this descriptor's directory identity are replaced.
    func prepareDescriptor(_ source: URL, in stagingRoot: URL) throws -> URL {
        let fm = FileManager.default
        _ = try PosterBoardStore.manifest(source) // rejects every symlink, including hidden ones
        let oldID = source.lastPathComponent
        let newID = UUID().uuidString
        let destination = stagingRoot.appendingPathComponent(newID, isDirectory: true)
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            var scanError: Error?
            guard let scan = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey],
                                           errorHandler: { _, error in scanError = error; return false }) else {
                throw PosterBoardStore.failure("Cannot enumerate wallpaper descriptor.")
            }
            for case let file as URL in scan {
                let name = file.lastPathComponent
                // This dot-prefixed Apple plist is functional, not Finder debris.
                let allowedHidden = name == ".com.apple.posterkit.provider.contents.configurableOptions.plist"
                if name == "__MACOSX" || (name.hasPrefix(".") && !allowedHidden) {
                    if (try file.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true { scan.skipDescendants() }
                    continue
                }
                let relative = String(file.path.dropFirst(source.path.count + 1))
                let target = destination.appendingPathComponent(relative)
                if (try file.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                    continue
                }
                try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let original = try Data(contentsOf: file)
                let bytes: Data
                if let object = try? PropertyListSerialization.propertyList(from: original, format: nil) {
                    let updated = remapDescriptorIdentity(object, oldID: oldID, newID: newID)
                    bytes = try PropertyListSerialization.data(fromPropertyList: updated, format: .binary, options: 0)
                } else if let text = String(data: original, encoding: .utf8) {
                    bytes = Data(remapDescriptorString(text, oldID: oldID, newID: newID).utf8)
                } else {
                    bytes = original
                }
                try bytes.write(to: target, options: .atomic)
            }
            if let scanError { throw scanError }
            _ = try PosterBoardStore.manifest(destination)
            return destination
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    private func remapDescriptorString(_ value: String, oldID: String, newID: String) -> String {
        if value == oldID { return newID }
        // A UUID is unambiguous even embedded in archived URL strings. Do not
        // globally replace short package names/numbers in artwork or metadata.
        if UUID(uuidString: oldID) != nil {
            return value.replacingOccurrences(of: oldID, with: newID, options: .caseInsensitive)
        }
        return value.replacingOccurrences(of: "/" + oldID + "/", with: "/" + newID + "/")
    }

    private func remapDescriptorIdentity(_ object: Any, oldID: String, newID: String) -> Any {
        if let string = object as? String {
            return remapDescriptorString(string, oldID: oldID, newID: newID)
        }
        if let array = object as? [Any] {
            return array.map { remapDescriptorIdentity($0, oldID: oldID, newID: newID) }
        }
        if let dictionary = object as? [String: Any] {
            // Keyed-archive UIDs, numeric wallpaper IDs and all non-string values
            // survive unchanged. Never partially randomize Wallpaper.plist.
            return dictionary.mapValues { remapDescriptorIdentity($0, oldID: oldID, newID: newID) }
        }
        return object
    }

    // MARK: - Find Descriptors With Targeted Extensions

    func isDescriptorFolder(_ url: URL) -> Bool {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
        let name = url.lastPathComponent
        if name.hasPrefix(".") || name == "__MACOSX" { return false }

        // Must not be the container root or Library itself
        let ignoredNames: Set<String> = [
            "container", "library", "application support", "prbposterextensiondatastore",
            "extensions", "descriptors", "ordered-descriptors",
            "mercury-descriptors", "mercurydescriptors", "video-descriptors", "videodescriptors"
        ]
        if ignoredNames.contains(name.lowercased()) {
            return false
        }

        // 1. Has "versions" directory
        let versions = url.appendingPathComponent("versions")
        if fm.fileExists(atPath: versions.path) { return true }

        // 2. Has "providerInfo.plist"
        let providerInfo = url.appendingPathComponent("providerInfo.plist")
        if fm.fileExists(atPath: providerInfo.path) { return true }

        // 3. Has "com.apple.posterkit.provider.descriptor.identifier"
        let descId = url.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier")
        if fm.fileExists(atPath: descId.path) { return true }

        // 4. Has "Wallpaper.plist"
        let wallpaper = url.appendingPathComponent("Wallpaper.plist")
        if fm.fileExists(atPath: wallpaper.path) { return true }

        // 5. Ends with .wallpaper
        if url.pathExtension.lowercased() == "wallpaper" { return true }

        return false
    }

    func determineExtension(for folderURL: URL, defaultExt: String) -> String {
        let pathLower = folderURL.path.lowercased()

        // 1. Check path components for .../Extensions/<bundleID>/descriptors/<desc>
        let components = folderURL.pathComponents
        for i in 0..<components.count {
            if components[i].lowercased() == "extensions", i + 1 < components.count {
                let cand = components[i + 1]
                if cand.contains(".") {
                    return cand
                }
            }
            if components[i].lowercased() == "descriptors", i > 0 {
                let cand = components[i - 1]
                if cand.contains(".") && !cand.lowercased().contains("store") {
                    return cand
                }
            }
        }

        // 2. Check metadata inside suggestionMetadata.plist if present
        let metadataURL = folderURL.appendingPathComponent("com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist")
        if let data = try? Data(contentsOf: metadataURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let objects = plist["$objects"] as? [Any] {
            for obj in objects {
                if let str = obj as? String {
                    if str.hasPrefix("com.apple.") && str.contains("Poster") {
                        return str
                    }
                }
            }
        }

        // 3. Check descriptor identifier content (e.g. "v6x.colorA" or "v5..." -> Mercury)
        let descIdURL = folderURL.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier")
        if let descId = try? String(contentsOf: descIdURL, encoding: .utf8) {
            let trimmed = descId.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("v6") || trimmed.hasPrefix("v5") || trimmed.hasPrefix("v4") || trimmed.contains(".color") {
                return "com.apple.MercuryPoster"
            }
        }

        // 4. Path string hints
        if pathLower.contains("mercury") {
            return "com.apple.MercuryPoster"
        }
        if pathLower.contains("video") || pathLower.contains("photo") {
            return "com.apple.PhotosUIPrivate.PhotosPosterProvider"
        }
        if pathLower.contains("collection") || pathLower.contains("wallpaperkit") {
            return "com.apple.WallpaperKit.CollectionsPoster"
        }
        if pathLower.contains("kaleidoscope") {
            return "com.apple.Posters.KaleidoscopePosterApp.KaleidoscopePoster"
        }
        if pathLower.contains("unity") {
            return "com.apple.Posters.UnityPosterApp.UnityPosterExtension"
        }

        return defaultExt
    }

    public func findDescriptorsWithExtensions(in rootURL: URL, defaultExt: String) -> [(ext: String, url: URL)] {
        let fileManager = FileManager.default
        var results: [(ext: String, url: URL)] = []

        if isDescriptorFolder(rootURL) {
            let ext = determineExtension(for: rootURL, defaultExt: defaultExt)
            return [(ext: ext, url: rootURL)]
        }

        // Recursive traversal to discover all descriptor directories
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let itemURL = enumerator.nextObject() as? URL {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: itemURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            if itemURL.lastPathComponent.hasPrefix(".") || itemURL.lastPathComponent == "__MACOSX" {
                enumerator.skipDescendants()
                continue
            }

            if isDescriptorFolder(itemURL) {
                let ext = determineExtension(for: itemURL, defaultExt: defaultExt)
                results.append((ext: ext, url: itemURL))
                enumerator.skipDescendants() // Do not look for nested descriptors inside a descriptor folder
            }
        }

        return results
    }
}
