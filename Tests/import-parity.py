"""Build actual-source SwiftPM fixtures. No access lease or device code runs."""
from pathlib import Path
import shutil, zipfile, plistlib
s = Path("Sources/ProbeImportParity.swift").read_text()
a = Path("Sources/TendiesArchive.swift").read_text()
run = Path("Sources/ProbeInstallTest.swift").read_text()
assert "ProbeImportParity.normalize" in run
assert 'sourceIdentifier == "7400"' in run
assert 'pending.json' in run
assert 'fm.copyItem(at: source, to: target)' in run
assert 'mkdir(target.path' not in run
assert "archive.extract(entry, to: target)" in a
assert "actualTotal <= 536_870_912" in a
for forbidden in ["PosterBoardLease", "sandbox", "grant(", "suggestionMetadata.plist"]:
    assert forbidden not in s
root = Path("/tmp/pb-import-parity-fixtures")
root.mkdir(exist_ok=True)
sources = root / "Sources" / "ParityFixtures"
sources.mkdir(parents=True, exist_ok=True)
for file in ["ProbeImportParity.swift", "TendiesArchive.swift"]:
    shutil.copyfile(Path("Sources") / file, sources / file)
store = Path("Sources/PosterBoardStore.swift").read_text()
manifest = store[store.index("    static func manifest("):store.index("    /// Copies only new descriptor")]
(sources / "Store.swift").write_text('''import Foundation
import CryptoKit
enum PosterBoardStore {
static func failure(_ message: String) -> NSError {
    NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}
''' + manifest + "\n}\n")
(root / "Package.swift").write_text('''// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "ParityFixtures", platforms: [.macOS(.v13)],
 dependencies: [.package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")],
 targets: [.executableTarget(name: "ParityFixtures", dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")])])
''')
prefix = "descriptors/00B33CEB-3768-4682-81AD-0384CDA80B22/"
payloads = {
    prefix + "com.apple.posterkit.provider.descriptor.identifier": b"7400",
    prefix + "versions/1/contents/com.apple.posterkit.provider.contents.userInfo":
        plistlib.dumps({"wallpaperRepresentingIdentifier": "7400", "wallpaperRepresentingFileName": "7400.wallpaper",
                       "nested": {"wallpaperRepresentingIdentifier": "7400"}}, fmt=plistlib.FMT_BINARY),
    prefix + "versions/1/contents/7400.wallpaper/Wallpaper.plist":
        plistlib.dumps({"identifier": 7400, "assets": {"lockAndHome": {"default": {"identifier": 7400}}}}, fmt=plistlib.FMT_XML),
    prefix + "com.apple.posterkit.provider.identifierURL.suggestionMetadata.plist":
        plistlib.dumps({"uuid": "00B33CEB-3768-4682-81AD-0384CDA80B22", "descriptorIdentifier": "7400.DYNAMIC"}, fmt=plistlib.FMT_BINARY),
    prefix + "versions/1/contents/7400.wallpaper/7400.caml": b"position animation 7400",
    prefix + ".DS_Store": b"finder debris",
    prefix + "versions/1/contents/.com.apple.posterkit.provider.contents.configurableOptions.plist": b"functional",
}
def write_zip(name, entries):
    with zipfile.ZipFile(root / name, "w") as z:
        for path, data, mode in entries:
            info = zipfile.ZipInfo(path, date_time=(2022, 6, 7, 8, 10, 12))
            info.create_system = 3
            info.external_attr = mode << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(info, data)
write_zip("good.tendies", [(prefix, b"", 0o40750)] +
          [(n, d, 0o100600) for n, d in payloads.items()])
for name, entries in {
    "traversal.tendies": [("../escape", b"x", 0o100600)],
    "symlink.tendies": [("link", b"/tmp/escape", 0o120777)],
    "duplicate.tendies": [("a", b"x", 0o100600), ("A", b"y", 0o100600)],
    "prefix-conflict.tendies": [("a", b"x", 0o100600), ("a/child", b"y", 0o100600)],
}.items():
    write_zip(name, entries)
(sources / "main.swift").write_text(r'''
import Foundation
import ZIPFoundation
let fm = FileManager.default
let root = URL(fileURLWithPath: "/tmp/pb-import-parity-fixtures")
let work = root.appendingPathComponent("run-" + UUID().uuidString)
try fm.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: work) }
let parser = TendiesArchive()
let extracted = work.appendingPathComponent("Extracted")
try fm.createDirectory(at: extracted, withIntermediateDirectories: false)
try parser.extractValidatedArchive(root.appendingPathComponent("good.tendies"), to: extracted)
let source = extracted.appendingPathComponent("descriptors/00B33CEB-3768-4682-81AD-0384CDA80B22")
let userPath = "versions/1/contents/com.apple.posterkit.provider.contents.userInfo"
let wallpaperPath = "versions/1/contents/7400.wallpaper/Wallpaper.plist"
let rawPath = "com.apple.posterkit.provider.descriptor.identifier"
let sourceMode = try fm.attributesOfItem(atPath: source.path)[.posixPermissions] as! NSNumber
precondition(sourceMode.intValue == 0o750)
let before = try PosterBoardStore.manifest(source)
precondition(before[".DS_Store"] == nil)
precondition(before["versions/1/contents/.com.apple.posterkit.provider.contents.configurableOptions.plist"] != nil)
let calendar = Calendar.current
for url in [source, source.appendingPathComponent(rawPath), source.appendingPathComponent(userPath)] {
    let attrs = try fm.attributesOfItem(atPath: url.path)
    let mode = attrs[.posixPermissions] as! NSNumber
    precondition(mode.intValue == (url == source ? 0o750 : 0o600))
    let date = attrs[.modificationDate] as! Date
    let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    precondition(c.year == 2022 && c.month == 6 && c.day == 7 && c.hour == 8 && c.minute == 10 && c.second == 12)
}
let changed = try ProbeImportParity.normalize(source: source, packageRoot: extracted, identifier: 53129)
precondition(changed == Set([rawPath, userPath, wallpaperPath]))
let after = try PosterBoardStore.manifest(source)
precondition(Set(before.keys) == Set(after.keys))
for key in before.keys where !changed.contains(key) { precondition(before[key] == after[key]) }
let raw = try String(contentsOf: source.appendingPathComponent(rawPath), encoding: .utf8)
precondition(raw == "53129")
func readPlist(_ path: String) throws -> ([String: Any], PropertyListSerialization.PropertyListFormat) {
    var format = PropertyListSerialization.PropertyListFormat.binary
    let data = try Data(contentsOf: source.appendingPathComponent(path))
    return (try PropertyListSerialization.propertyList(from: data, format: &format) as! [String: Any], format)
}
let (user, uf) = try readPlist(userPath)
precondition(uf == .binary)
precondition(user["wallpaperRepresentingIdentifier"] is NSNumber)
precondition(!(user["wallpaperRepresentingIdentifier"] is String))
precondition((user["wallpaperRepresentingIdentifier"] as? Int) == 53129)
precondition(user["wallpaperRepresentingFileName"] as? String == "7400.wallpaper")
precondition((user["nested"] as! [String: Any])["wallpaperRepresentingIdentifier"] as? String == "7400")
let (wallpaper, wf) = try readPlist(wallpaperPath)
precondition(wf == .xml)
precondition(wallpaper["identifier"] as? Int == 53129)
let assets = wallpaper["assets"] as! [String: Any]
let combined = assets["lockAndHome"] as! [String: Any]
precondition((combined["default"] as! [String: Any])["identifier"] as? Int == 7400)
let containerRoot = extracted.appendingPathComponent("cOnTaInEr")
try fm.createDirectory(at: containerRoot, withIntermediateDirectories: false)
let containerSource = containerRoot.appendingPathComponent("descriptor")
try fm.copyItem(at: source, to: containerSource)
let skipped = try ProbeImportParity.normalize(source: containerSource, packageRoot: extracted, identifier: 65000)
precondition(skipped.isEmpty)
let skippedManifest = try PosterBoardStore.manifest(containerSource)
precondition(skippedManifest == after)
let substring = try ProbeImportParity.shouldNormalize(source: extracted.appendingPathComponent("MyContainerName/descriptor"), packageRoot: extracted)
precondition(substring)
do {
    _ = try ProbeImportParity.shouldNormalize(source: root, packageRoot: extracted)
    fatalError("outside package accepted")
} catch {}
for name in ["traversal", "symlink", "duplicate", "prefix-conflict"] {
    let dest = work.appendingPathComponent(name)
    try fm.createDirectory(at: dest, withIntermediateDirectories: false)
    do {
        try parser.extractValidatedArchive(root.appendingPathComponent(name + ".tendies"), to: dest)
        fatalError("unsafe archive accepted")
    } catch {}
}
let nonempty = work.appendingPathComponent("nonempty")
try fm.createDirectory(at: nonempty, withIntermediateDirectories: false)
try fm.createSymbolicLink(at: nonempty.appendingPathComponent("descriptors"), withDestinationURL: root)
do {
    try parser.extractValidatedArchive(root.appendingPathComponent("good.tendies"), to: nonempty)
    fatalError("preexisting symlink root accepted")
} catch {}
precondition(ProbeImportParity.isDuplicate(identifier: "7400", directory: UUID().uuidString,
 originalIdentifier: "7400", normalizedIdentifier: "53129", sourceDirectory: source.lastPathComponent))
precondition(ProbeImportParity.isDuplicate(identifier: "53129", directory: UUID().uuidString,
 originalIdentifier: "7400", normalizedIdentifier: "53129", sourceDirectory: source.lastPathComponent))
precondition(ProbeImportParity.isDuplicate(identifier: "different", directory: "BE2EE206-9948-4F2B-BD3E-C02042EDBC5D",
 originalIdentifier: "7400", normalizedIdentifier: "53129", sourceDirectory: source.lastPathComponent))
precondition(!ProbeImportParity.isDuplicate(identifier: "other", directory: UUID().uuidString,
 originalIdentifier: "7400", normalizedIdentifier: "53129", sourceDirectory: source.lastPathComponent))
print("IMPORT PARITY FIXTURES PASS · extraction attributes, limits, three fields, nested preservation, conditional Container and prior-copy refusal")
''')
print("IMPORT PARITY actual-source fixtures generated")
