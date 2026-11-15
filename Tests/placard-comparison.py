"""Compile the entire actual read-only collector on macOS, with no device lease."""
from pathlib import Path
s = Path("Sources/ProbePlacardComparison.swift").read_text()
app = Path("Sources/PBProbeApp.swift").read_text()
for forbidden in [".write(", "createDirectory", "removeItem", "copyItem", "mkdir(", "O_CREAT", "O_WRONLY", "UserDefaults", "setxattr(", "unlink(", "rename("]:
    assert forbidden not in s, forbidden
assert "lease.grant(relative) && lease.permits" in s
assert "var grants = 128" in s and "var seconds: Double = 30" in s and "8_388_608" in s
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
 static func validateIdentity(_ url: URL, lease: PosterBoardLease, rule: IdentityRule) throws {
  if PosterBoardLease.failIdentity { throw failure("injected identity failure") }
 }
}
final class PosterBoardLease {
 static var closed = 0
 static var failIdentity = false
 static var failClose = false
 static var handler: (String) -> Bool = { _ in true }
 let effectiveURL: URL
 init(path: String, log: @escaping (String) -> Void) throws { effectiveURL = URL(fileURLWithPath: path) }
 func grant(_ path: String) -> Bool { Self.handler(path) }
 func permits(_ url: URL) -> Bool { true }
 func close() throws {
  Self.closed += 1
  if Self.failClose { throw PosterBoardStore.failure("injected cleanup failure") }
 }
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
for marker in ["BOUNDED OBSERVED DESCRIPTOR SIBLINGS (3)", "CANDIDATE " + candidate.path.replacingOccurrences(of: base.path + "/", with: ""), "DIFF", "FULL STRUCTURED CONTENT", "secretNested", "wallpaperRepresentingIdentifier", "55667", "47891", "<integer>7400</integer>", "hidden", "user.pbprobe.fixture", "SKIP nonregular/link", "LIMIT payload unread", "incomplete=true"] {
 precondition(report.contains(marker), "Missing marker " + marker)
}
precondition(!report.contains("MUST_NOT_DUMP"))
precondition(!report.contains("DO_NOT_READ_SYMLINK_TARGET"))
let denied = try ProbePlacardComparison.collect(base: base, allow: { !$0.hasSuffix("Wallpaper.plist") })
precondition(denied.contains("DENIED/REDIRECTED"))
let deniedRoot = try ProbePlacardComparison.collect(base: base, allow: { _ in false })
precondition(deniedRoot.contains("COMPARE SNAPSHOT END") && deniedRoot.contains("DENIED/REDIRECTED ancestor"))
let binary = try PropertyListSerialization.data(fromPropertyList: ["id": Data([1,2])], format: .binary, options: 0)
precondition(ProbePlacardComparison.decoded(binary).0!.contains("<data>"))

// Thousands of unrelated trees and unrelated sibling versions are never granted or traversed.
for provider in ["ClockPoster", "PhotosPoster", "PhotosAmbientPoster"] {
 try put(base.appendingPathComponent(ProbePlacardComparison.store + "/Extensions/com.apple.WallpaperKit." + provider + "/versions/1/forbidden.txt"), Data("UNRELATED_SENTINEL".utf8))
}
try put(other.appendingPathComponent("versions/1/private.txt"), Data("SIBLING_FORBIDDEN".utf8))
var granted: [String] = []
let bounded = try ProbePlacardComparison.collect(base: base, allow: { path in
 granted.append(path)
 precondition(!path.contains("ClockPoster") && !path.contains("Photos") && !path.contains("/Other/") && !path.hasSuffix("gallery-index.json"))
 precondition(!path.hasPrefix(ProbePlacardComparison.parent + "/" + other.lastPathComponent + "/versions"))
 return true
})
let firstDescriptor = granted.first { $0.hasPrefix(ProbePlacardComparison.parent + "/") }!
precondition(firstDescriptor == ProbePlacardComparison.parent + "/" + ProbePlacardComparison.ours)
let candidateAsset = ProbePlacardComparison.parent + "/" + candidateID + "/assets/a.png"
let candidateMetadata = ProbePlacardComparison.parent + "/" + candidateID + "/Wallpaper.plist"
precondition(granted.firstIndex(of: candidateMetadata)! < granted.firstIndex(of: candidateAsset)!)
precondition(!bounded.contains("UNRELATED_SENTINEL") && !bounded.contains("SIBLING_FORBIDDEN"))
precondition(!bounded.contains("Other/sub/index.plist"))
// Tiny grant cap stops acquisition and retains own-root observations.
var cap = ProbePlacardComparison.Limits()
cap.grants = ProbePlacardComparison.parent.split(separator: "/").count + 2
var capCalls = 0
let capReport = try ProbePlacardComparison.collect(base: base, allow: { _ in capCalls += 1; return true }, limits: cap)
precondition(capCalls == cap.grants)
precondition(capReport.contains("LIMIT total grant attempts") && capReport.contains("COMPARE SNAPSHOT END"))
precondition(capReport.contains(ProbePlacardComparison.ours + " type=dir"))
// Inject time advancing in an expensive allow, without sleeping or real resource acquisition.
var tick: Double = 0
var timeCalls = 0
var timed = ProbePlacardComparison.Limits()
timed.seconds = 3
let timedReport = try ProbePlacardComparison.collect(base: base, allow: { _ in
 timeCalls += 1; tick += 1; return true
}, limits: timed, now: { tick })
precondition(timeCalls == 3 && timedReport.contains("LIMIT cooperative"))
var denialCalls = 0
let denialReport = try ProbePlacardComparison.collect(base: base, allow: { path in
 if path.hasPrefix(ProbePlacardComparison.parent + "/") { denialCalls += 1; return false }
 return true
})
precondition(denialCalls == 2 && denialReport.contains("COMPARE SNAPSHOT END"))
// Entry, shallow-name, read, depth and sibling bounds execute actual collector code.
var tiny = ProbePlacardComparison.Limits()
tiny.entries = 2
precondition(try ProbePlacardComparison.collect(base: base, allow: { _ in true }, limits: tiny).contains("LIMIT cooperative"))
tiny = ProbePlacardComparison.Limits(); tiny.names = 1
precondition(try ProbePlacardComparison.collect(base: base, allow: { _ in true }, limits: tiny).contains("LIMIT shallow names"))
tiny = ProbePlacardComparison.Limits(); tiny.bytes = 1
precondition(try ProbePlacardComparison.collect(base: base, allow: { _ in true }, limits: tiny).contains("LIMIT payload"))
tiny = ProbePlacardComparison.Limits(); tiny.depth = 0
precondition(try ProbePlacardComparison.collect(base: base, allow: { _ in true }, limits: tiny).contains("LIMIT depth"))
tiny = ProbePlacardComparison.Limits(); tiny.siblings = 1
precondition(try ProbePlacardComparison.collect(base: base, allow: { _ in true }, limits: tiny).contains("LIMIT metadata sibling"))
// Final path identity failure preserves previously read hashes/content instead of throwing it away.
let moved = parent.appendingPathExtension("moved")
var replaced = false
let changedReport = try ProbePlacardComparison.collect(base: base, allow: { _ in true }, progress: { phase in
 if phase.hasPrefix("COMPARE PHASE selected"), !replaced {
  try! fm.moveItem(at: parent, to: moved)
  try! fm.createDirectory(at: parent, withIntermediateDirectories: false)
  replaced = true
 }
})
precondition(changedReport.contains("FINAL REVALIDATION FAILED") && changedReport.contains("secretNested"))
try fm.removeItem(at: parent)
try fm.moveItem(at: moved, to: parent)
// Actual run lifecycle closes the lease once for normal, partial, validation and cleanup errors.
PosterBoardLease.closed = 0
let normalRun = try ProbePlacardComparison.run(path: base.path, log: { _ in })
precondition(PosterBoardLease.closed == 1 && normalRun.contains("AUDIT COMPARE COMPLETE"))
PosterBoardLease.closed = 0
PosterBoardLease.handler = { !$0.hasSuffix("Wallpaper.plist") }
let partialRun = try ProbePlacardComparison.run(path: base.path, log: { _ in })
precondition(PosterBoardLease.closed == 1 && partialRun.contains("COMPARE SNAPSHOT END") && partialRun.contains("DENIED/REDIRECTED"))
PosterBoardLease.closed = 0; PosterBoardLease.failIdentity = true
let identityRun = try ProbePlacardComparison.run(path: base.path, log: { _ in })
precondition(PosterBoardLease.closed == 1 && identityRun.contains("injected identity failure"))
PosterBoardLease.failIdentity = false; PosterBoardLease.failClose = true
PosterBoardLease.handler = { _ in true }; PosterBoardLease.closed = 0
let closeRun = try ProbePlacardComparison.run(path: base.path, log: { _ in })
precondition(PosterBoardLease.closed == 1 && closeRun.contains("CLEANUP ERROR") && closeRun.contains("secretNested"))
print("READONLY PLACARD COMPARISON FIXTURES PASS full-tree/plists/identity/xattrs/hash/diff/no-writes/link/fifo/oversize/denied")
print("BOUNDED COLLECTION FIXTURES PASS unrelated-never-granted/own-first/metadata-before-assets/time/grants/denials/entries/names/reads/depth/siblings/partial-final-revalidation/leaseclose")
'''
# Swift throwing expression cannot live in a precondition autoclosure.
fixture = fixture.replace("precondition(try snapshot() == before)", "let after = try snapshot()\nprecondition(after == before)")
lines = []
for i, line in enumerate(fixture.splitlines()):
    if line.startswith("precondition(try "):
        lines.extend([f"let throwingCheck{i} = try " + line[len("precondition(try "):-1], f"precondition(throwingCheck{i})"])
    else:
        lines.append(line)
fixture = "\n".join(lines)
Path("/tmp/pb-placard-comparison-fixtures.swift").write_text(stub + Path("Sources/ApprovedAnimeManifest.swift").read_text() + s + fixture)
print("READONLY PLACARD COMPARISON SOURCE BOUNDS PASS")
