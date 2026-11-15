from pathlib import Path
s = Path("Sources/ProbeInstallTest.swift").read_text()
assert "PosterBoardStore.install(" not in s
assert "PosterBoardStore.layout(" not in s
assert 'let name = UUID().uuidString' in s
assert "expectedPaths" in s and "current.st_ino == owned.st_ino" in s
for banned in ['PBF_', 'PersistedPoster', 'resetProtections:', 'prepareDescriptor(']:
    assert banned not in s
assert 'digest == approvedSHA256' in s
assert 'descriptors.count == 1' in s
assert 'identifier != sourceIdentifier' in s
assert 'pending.json' in s
a = Path("Sources/PBProbeApp.swift").read_text()
assert 'Button("Test Install") { model.run(apply: false, install: true) }' in a
assert "Gallery visibility and activation UNVERIFIED" in a
store = Path("Sources/PosterBoardStore.swift").read_text()
manifest = store[store.index("    static func manifest("):store.index("    /// Copies only new descriptor")]
helpers = s[s.index("    static func relativePaths("):]
fixture = '''
import Foundation
import CryptoKit
import Darwin
enum PosterBoardStore {
    static func failure(_ message: String) -> NSError {
        NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
''' + manifest + "\n}\nenum ProbeInstallTest {\n" + helpers + '''
let fm = FileManager.default
let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: root) }
let source = root.appendingPathComponent("source")
try fm.createDirectory(at: source.appendingPathComponent("versions/1"), withIntermediateDirectories: true)
try Data("unchanged wallpaper".utf8).write(to: source.appendingPathComponent("versions/1/payload"))
let expected = try PosterBoardStore.manifest(source)
precondition(Set(expected.keys) == ["versions/1/payload"])
let sourcePaths = try ProbeInstallTest.relativePaths(source)
precondition(sourcePaths == ["versions", "versions/1", "versions/1/payload"])
let aliasRoot = root.appendingPathComponent("alias")
try fm.createSymbolicLink(at: aliasRoot, withDestinationURL: root)
let aliasSource = aliasRoot.appendingPathComponent("source")
let aliasManifest = try PosterBoardStore.manifest(aliasSource)
precondition(aliasManifest == expected)
let aliasPaths = try ProbeInstallTest.relativePaths(aliasSource)
precondition(aliasPaths == sourcePaths)
let target = root.appendingPathComponent("target")
try ProbeInstallTest.copyExclusive(source: source, target: target, expected: expected, log: { _ in })
precondition(try PosterBoardStore.manifest(target) == expected)
do {
    try ProbeInstallTest.copyExclusive(source: source, target: target, expected: expected, log: { _ in })
    fatalError("collision accepted")
} catch {}
precondition(try PosterBoardStore.manifest(target) == expected)
let redirected = root.appendingPathComponent("redirected")
try fm.createSymbolicLink(at: redirected, withDestinationURL: target)
do {
    try ProbeInstallTest.copyExclusive(source: source, target: redirected, expected: expected, log: { _ in })
    fatalError("symlink accepted")
} catch {}
precondition(try PosterBoardStore.manifest(target) == expected)
let mismatch = root.appendingPathComponent("mismatch")
do {
    try ProbeInstallTest.copyExclusive(source: source, target: mismatch, expected: ["versions/1/payload": "bad"], log: { _ in })
    fatalError("mismatch accepted")
} catch {}
precondition(fm.fileExists(atPath: mismatch.path)) // preserve unknown bytes
print("INSTALL COPY FIXTURES PASS: unchanged copy, collision, symlink, mismatch preservation")
'''
# Throwing expressions cannot be evaluated in precondition autoclosures.
fixture = fixture.replace('precondition(try PosterBoardStore.manifest(target) == expected)',
                          'do { let actual = try PosterBoardStore.manifest(target); precondition(actual == expected) }')
Path("/tmp/pb-install-fixtures.swift").write_text(fixture)
print("PASS isolated install source invariants; Swift copy fixture generated")
