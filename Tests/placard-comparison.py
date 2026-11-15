"""Compile the entire actual read-only collector on macOS, with no device lease."""
from pathlib import Path
s = Path("Sources/ProbePlacardComparison.swift").read_text()
app = Path("Sources/PBProbeApp.swift").read_text()
for forbidden in [".write(", "createDirectory", "removeItem", "copyItem", "mkdir(", "O_CREAT", "O_WRONLY", "UserDefaults", "setxattr(", "unlink(", "rename("]:
    assert forbidden not in s, forbidden
assert "lease.grant(relative) && lease.permits" in s
assert "8192" in s and "100_663_296" in s and "8_388_608" in s
assert "openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK" in s
assert "AT_SYMLINK_NOFOLLOW" in s and "flistxattr" in s
assert 'Button("Compare With Placard")' in app
assert "guard !apply && !cleanup && !install && !reconcile else" in app
assert 'if let report = path.1 { append(report) }' in app
stub = r'''
import Foundation
enum IdentityRule { case strict }
enum PosterBoardStore {
 static func failure(_ message: String) -> NSError {
  NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
 }
 static func validateIdentity(_ url: URL, lease: PosterBoardLease, rule: IdentityRule) throws {}
}
final class PosterBoardLease {
 let effectiveURL: URL
 init(path: String, log: @escaping (String) -> Void) throws { effectiveURL = URL(fileURLWithPath: path) }
 func grant(_ path: String) -> Bool { false }
 func permits(_ url: URL) -> Bool { false }
 func close() throws {}
}
'''
fixture = r'''
let fm = FileManager.default
let base = fm.temporaryDirectory.appendingPathComponent("pb-compare-" + UUID().uuidString)
try fm.createDirectory(at: base, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: base) }
let parent = base.appendingPathComponent(ProbePlacardComparison.parent)
let our = parent.appendingPathComponent(ProbePlacardComparison.ours)
let candidateID = "CD123456-1234-1234-1234-123456789ABC"
let candidate = parent.appendingPathComponent(candidateID)
func put(_ url: URL, _ bytes: Data) throws {
 try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
 try bytes.write(to: url)
}
for directory in [our, candidate] {
 try put(directory.appendingPathComponent("assets/a.png"), Data([1,2,3]))
 try put(directory.appendingPathComponent("assets/b.png"), Data([4,5,6]))
 let value: [String: Any] = ["identifier": directory == our ? 47891 : 55667,
   "assets": ["lockAndHome": ["default": ["identifier": 7400]]],
   "title": "Anime-Squad", "blob": Data([10,20,30])]
 try put(directory.appendingPathComponent("Wallpaper.plist"),
   PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0))
 try put(directory.appendingPathComponent("com.apple.posterkit.provider.contents.userInfo"),
   PropertyListSerialization.data(fromPropertyList: ["wallpaperRepresentingIdentifier": 7400, "secretNested": ["present": true]], format: .binary, options: 0))
 try put(directory.appendingPathComponent(".hidden.plist"),
   PropertyListSerialization.data(fromPropertyList: ["hidden": "included"], format: .xml, options: 0))
}
let other = parent.appendingPathComponent("EF123456-1234-1234-1234-123456789ABC")
try put(other.appendingPathComponent("Wallpaper.plist"),
 PropertyListSerialization.data(fromPropertyList: ["title": "not a match", "privateUnrelated": "MUST_NOT_DUMP"], format: .binary, options: 0))
let index = base.appendingPathComponent(ProbePlacardComparison.store + "/PRPosterRoleLockScreen-gallery-index.json")
try put(index, Data(("{\"uuid\":\"" + candidateID + "\",\"our\":\"" + ProbePlacardComparison.ours + "\"}").utf8))
let ref = base.appendingPathComponent(ProbePlacardComparison.store + "/Other/sub/index.plist")
try put(ref, PropertyListSerialization.data(fromPropertyList: ["nested": [candidateID]], format: .binary, options: 0))
let outside = base.appendingPathComponent("outside.txt")
try put(outside, Data("DO_NOT_READ_SYMLINK_TARGET".utf8))
try fm.createSymbolicLink(at: our.appendingPathComponent("link"), withDestinationURL: outside)
let fifo = our.appendingPathComponent("fifo")
precondition(mkfifo(fifo.path, 0o600) == 0)
let oversized = our.appendingPathComponent("oversize")
precondition(fm.createFile(atPath: oversized.path, contents: nil))
let output = try FileHandle(forWritingTo: oversized)
try output.truncate(atOffset: 8_388_609)
try output.close()
let xfile = our.appendingPathComponent("assets/a.png")
let xbytes: [UInt8] = [7]
precondition(xbytes.withUnsafeBytes { setxattr(xfile.path, "user.pbprobe.fixture", $0.baseAddress, 1, 0, 0) } == 0)
func snapshot() throws -> [String: String] {
 var result: [String: String] = [:]
 for case let url as URL in fm.enumerator(at: base, includingPropertiesForKeys: nil)! {
  let a = try fm.attributesOfItem(atPath: url.path)
  result[url.path] = "\(a[.type]!) \(a[.size]!) \(a[.posixPermissions]!) \(a[.modificationDate]!)"
 }
 return result
}
let before = try snapshot()
let report = try ProbePlacardComparison.collect(base: base, allow: { _ in true })
precondition(try snapshot() == before)
for marker in ["ALL DESCRIPTOR SIBLINGS (3)", "CANDIDATE " + candidate.path.replacingOccurrences(of: base.path + "/", with: ""), "DIFF", "FULL STRUCTURED CONTENT", "secretNested", "wallpaperRepresentingIdentifier", "55667", "47891", "<integer>7400</integer>", "hidden", "Other/sub/index.plist", "FULL REFERENCING INDEX", "user.pbprobe.fixture", "SKIP nonregular/link", "LIMIT payload unread", "incomplete=true"] {
 precondition(report.contains(marker), "Missing marker " + marker)
}
precondition(!report.contains("MUST_NOT_DUMP"))
precondition(!report.contains("DO_NOT_READ_SYMLINK_TARGET"))
let denied = try ProbePlacardComparison.collect(base: base, allow: { !$0.hasSuffix("Wallpaper.plist") })
precondition(denied.contains("DENIED/REDIRECTED"))
do {
 _ = try ProbePlacardComparison.collect(base: base, allow: { _ in false })
 fatalError("Denied root accepted")
} catch {}
let binary = try PropertyListSerialization.data(fromPropertyList: ["id": Data([1,2])], format: .binary, options: 0)
precondition(ProbePlacardComparison.decoded(binary).0!.contains("<data>"))
print("READONLY PLACARD COMPARISON FIXTURES PASS full-tree/plists/identity/index/other-directory/xattrs/hash/diff/no-writes/link/fifo/oversize/denied")
'''
# Swift throwing expression cannot live in a precondition autoclosure.
fixture = fixture.replace("precondition(try snapshot() == before)", "let after = try snapshot()\nprecondition(after == before)")
Path("/tmp/pb-placard-comparison-fixtures.swift").write_text(stub + Path("Sources/ApprovedAnimeManifest.swift").read_text() + s + fixture)
print("READONLY PLACARD COMPARISON SOURCE BOUNDS PASS")
