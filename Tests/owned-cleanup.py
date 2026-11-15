"""Execute actual-source cleanup primitives on private macOS temporary fixtures only."""
from pathlib import Path
s = Path("Sources/ProbeOwnedAnimeCleanup.swift").read_text()
ui = Path("Sources/PBProbeApp.swift").read_text()
assert 'guard !apply && !cleanup else' in ui  # removal remains model-blocked
assert 'try ProbeOwnedAnimeCleanup.run(path: path, log: logger)' in ui
assert 'B6DDAE7B-791A-4618-A85E-D9AC55BDF09E' in s
assert 'BE2EE206-9948-4F2B-BD3E-C02042EDBC5D' in s
assert '"/61/Extensions/"' in s
assert s.index('try tree.backup(to: evidence)') < s.index('try tree.removeVerified()')
assert s.index('try tree.removeVerified()') < s.index('try lease.close()') < s.index('try fm.moveItem(at: pending,')
for banned in ['removeItem(', 'PosterBoardStore.install(', 'resetProtections:', 'PRPosterRoleLockScreen-gallery-index', 'UserDefaults', 'discover(']:
    assert banned not in s
assert 'AT_REMOVEDIR' in s and 'AT_SYMLINK_NOFOLLOW' in s and 'st_nlink == 1' in s
assert 'try validateRecord(record, path: path)' in s
assert 'ApprovedAnimeManifest.files' in s
store = Path("Sources/PosterBoardStore.swift").read_text()
manifest = store[store.index("    static func manifest("):store.index("    /// Copies only new descriptor")]
canonical = store[store.index("    static let roots ="):store.index("    static func normalizedPath(")]
stub = """
import Foundation
import CryptoKit
import Darwin
enum IdentityRule { case strict }
enum PosterBoardStore {
""" + canonical + manifest + """
    static func validateIdentity(_ url: URL, lease: PosterBoardLease, rule: IdentityRule) throws {
        fatalError("fixture must never access a real container")
    }
}
enum ProbeInstallTest {
    static let store = "Library/Application Support/PRBPosterExtensionDataStore"
    static let provider = "com.apple.WallpaperKit.CollectionsPoster"
    static let approvedSHA256 = "ddb823145d1d3fa20ff83dff10de37b6c8e6d454863aa6a81b2125139200b66a"
}
enum ProbeDiagnostics {
    static func identifiesPosterBoard(_ path: String, log: (String) -> Void) throws -> Bool {
        fatalError("fixture must never discover a real container")
    }
}
final class PosterBoardLease {
    var effectiveURL: URL { fatalError("no device access") }
    init(path: String, log: @escaping (String) -> Void) throws { fatalError("no device access") }
    func grant(_ path: String) -> Bool { fatalError("no device access") }
    func permits(_ url: URL) -> Bool { fatalError("no device access") }
    func close() throws { fatalError("no device access") }
}
"""
test = r'''
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent("pb-cleanup-" + UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: root) }
func refuse(_ label: String, _ action: () throws -> Void) {
    do { try action(); fatalError("accepted unsafe " + label) } catch {}
}
let fakeContainer = "/var/mobile/Containers/Data/InternalDaemon/AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
let record: [String: Any] = [
    "container": fakeContainer, "relative": ProbeOwnedAnimeCleanup.relative,
    "archiveSHA256": ProbeInstallTest.approvedSHA256, "sourceIdentifier": "7400",
    "existingFilesModified": false, "preferencesModified": false, "registrationIPC": false,
    "galleryVerified": false, "expected": ApprovedAnimeManifest.files
]
func encoded(_ r: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: r) }
try ProbeOwnedAnimeCleanup.validateRecord(encoded(record), path: fakeContainer)
let recordMutations: [(String, Any)] = [
    ("relative", ProbeOwnedAnimeCleanup.relative.replacingOccurrences(of: "/61/", with: "/62/")),
    ("relative", ProbeOwnedAnimeCleanup.relative.replacingOccurrences(of: ProbeOwnedAnimeCleanup.descriptor, with: UUID().uuidString)),
    ("container", "/var/mobile/Containers/Data/InternalDaemon/BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"),
    ("archiveSHA256", "bad"), ("sourceIdentifier", "53129"),
    ("expected", ["foreign": "hash"]), ("normalizedIdentifier", 53129),
    ("existingFilesModified", true), ("preferencesModified", true), ("registrationIPC", true), ("galleryVerified", true)
]
for (key, value) in recordMutations {
    var changed = record; changed[key] = value
    refuse("journal " + key) { try ProbeOwnedAnimeCleanup.validateRecord(encoded(changed), path: fakeContainer) }
}
var missing = record; missing.removeValue(forKey: "expected")
refuse("missing manifest") { try ProbeOwnedAnimeCleanup.validateRecord(encoded(missing), path: fakeContainer) }

let fileBytes = ["identity": Data("7400".utf8), "versions/1/payload": Data("private test".utf8)]
let expected = fileBytes.mapValues { ProbeOwnedAnimeCleanup.digest($0) }
func make(_ label: String) throws -> (URL, URL) {
    let parent = root.appendingPathComponent(label)
    let target = parent.appendingPathComponent(ProbeOwnedAnimeCleanup.descriptor)
    try fm.createDirectory(at: target.appendingPathComponent("versions/1"), withIntermediateDirectories: true)
    for (path, bytes) in fileBytes { try bytes.write(to: target.appendingPathComponent(path)) }
    try Data("OTHER WALLPAPER MUST STAY".utf8).write(to: parent.appendingPathComponent("unrelated-sibling"))
    return (parent, target)
}
func unchanged(_ parent: URL, _ target: URL) throws {
    let m = try PosterBoardStore.manifest(target); precondition(m == expected)
    let sibling = try String(contentsOf: parent.appendingPathComponent("unrelated-sibling"), encoding: .utf8)
    precondition(sibling == "OTHER WALLPAPER MUST STAY")
}
let (goodParent, good) = try make("good")
do {
    let tree = try ProbeOwnedAnimeCleanup.Tree(parent: goodParent, name: ProbeOwnedAnimeCleanup.descriptor, expected: expected)
    let evidence = root.appendingPathComponent("evidence")
    try fm.createDirectory(at: evidence, withIntermediateDirectories: false)
    try tree.backup(to: evidence)
    let m = try PosterBoardStore.manifest(evidence.appendingPathComponent("descriptor-backup"))
    precondition(m == expected)
    try tree.removeVerified()
    precondition(!fm.fileExists(atPath: good.path))
    let sibling = try String(contentsOf: goodParent.appendingPathComponent("unrelated-sibling"), encoding: .utf8)
    precondition(sibling == "OTHER WALLPAPER MUST STAY")
}
for label in ["extra-file", "extra-directory", "missing", "changed", "symlink-file", "symlink-dir", "hardlink", "fifo", "root-symlink"] {
    let (parent, target) = try make(label)
    let file = target.appendingPathComponent("identity")
    switch label {
    case "extra-file": try Data("foreign".utf8).write(to: target.appendingPathComponent("foreign"))
    case "extra-directory": try fm.createDirectory(at: target.appendingPathComponent("foreign-dir"), withIntermediateDirectories: false)
    case "missing": try fm.removeItem(at: file)
    case "changed": try Data("changed".utf8).write(to: file)
    case "symlink-file":
        try fm.removeItem(at: file)
        try fm.createSymbolicLink(at: file, withDestinationURL: parent.appendingPathComponent("unrelated-sibling"))
    case "symlink-dir":
        try fm.removeItem(at: target.appendingPathComponent("versions"))
        try fm.createSymbolicLink(at: target.appendingPathComponent("versions"), withDestinationURL: root)
    case "hardlink": precondition(link(file.path, parent.appendingPathComponent("external-link").path) == 0)
    case "fifo":
        try fm.removeItem(at: file)
        precondition(mkfifo(file.path, 0o600) == 0)
    case "root-symlink":
        let moved = parent.appendingPathComponent("saved")
        try fm.moveItem(at: target, to: moved)
        try fm.createSymbolicLink(at: target, withDestinationURL: moved)
    default: fatalError()
    }
    refuse(label) { _ = try ProbeOwnedAnimeCleanup.Tree(parent: parent, name: ProbeOwnedAnimeCleanup.descriptor, expected: expected) }
    precondition(fm.fileExists(atPath: parent.appendingPathComponent("unrelated-sibling").path))
}
for label in ["file-replaced", "file-mutated", "root-replaced", "parent-replaced", "added-after", "directory-replaced", "parent-validation", "backup-collision"] {
    let (parent, target) = try make(label)
    var permitted = true
    let tree = try ProbeOwnedAnimeCleanup.Tree(parent: parent, name: ProbeOwnedAnimeCleanup.descriptor, expected: expected) {
        guard permitted else { throw ProbeOwnedAnimeCleanup.fail("fixture denied parent validation") }
    }
    let file = target.appendingPathComponent("identity")
    switch label {
    case "file-replaced":
        try Data("7400".utf8).write(to: target.appendingPathComponent("replacement"))
        try fm.removeItem(at: file)
        try fm.moveItem(at: target.appendingPathComponent("replacement"), to: file)
    case "file-mutated": try Data("different bytes".utf8).write(to: file)
    case "root-replaced":
        try fm.moveItem(at: target, to: parent.appendingPathComponent("old-owned"))
        try fm.createDirectory(at: target, withIntermediateDirectories: false)
    case "parent-replaced":
        try fm.moveItem(at: parent, to: root.appendingPathComponent(label + "-moved"))
        try fm.createDirectory(at: parent, withIntermediateDirectories: false)
    case "added-after": try Data("new foreign bytes".utf8).write(to: target.appendingPathComponent("foreign"))
    case "directory-replaced":
        let dir = target.appendingPathComponent("versions/1")
        try fm.moveItem(at: dir, to: parent.appendingPathComponent("old-dir"))
        try fm.createDirectory(at: dir, withIntermediateDirectories: false)
        try fileBytes["versions/1/payload"]!.write(to: dir.appendingPathComponent("payload"))
    case "parent-validation": permitted = false
    case "backup-collision":
        let ev = root.appendingPathComponent("bad-evidence")
        try fm.createDirectory(at: ev.appendingPathComponent("descriptor-backup"), withIntermediateDirectories: true)
        refuse(label) { try tree.backup(to: ev) }
        try unchanged(parent, target)
        continue
    default: fatalError()
    }
    refuse(label) { try tree.removeVerified() }
    // A changed snapshot must stop before deleting any original approved file.
    let original = label == "parent-replaced"
        ? root.appendingPathComponent(label + "-moved").appendingPathComponent(ProbeOwnedAnimeCleanup.descriptor)
        : (label == "root-replaced" ? parent.appendingPathComponent("old-owned") : target)
    precondition(fm.fileExists(atPath: original.appendingPathComponent("identity").path))
}
print("OWNED ANIME CLEANUP FIXTURES PASS · exact journal/manifest, backup, exclusive deletion, siblings, missing/extra/changed files, symlinks, hardlinks, FIFO, replacement races and backup failure")
'''
Path("/tmp/pb-owned-cleanup-fixtures.swift").write_text(
    stub + Path("Sources/ApprovedAnimeManifest.swift").read_text() + s + test
)
print("OWNED CLEANUP actual-source fixtures generated; no device access")
