from pathlib import Path
source = Path("Sources/ProbeWriteTest.swift").read_text()
body = source[source.index("    static func exclusiveRoundTrip"):]
tests = r'''
let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let payload = Data("access-fixture".utf8)
let test = root.appendingPathComponent(".pb-test")
try ProbeWriteTest.exclusiveRoundTrip(test, payload: payload, log: { print($0) })
precondition(!FileManager.default.fileExists(atPath: test.path))
try payload.write(to: test)
do {
    try ProbeWriteTest.exclusiveRoundTrip(test, payload: Data("wrong".utf8), log: { _ in })
    fatalError("Existing file overwritten")
} catch {}
precondition(try Data(contentsOf: test) == payload)
let link = root.appendingPathComponent(".pb-link")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: test)
do {
    try ProbeWriteTest.exclusiveRoundTrip(link, payload: payload, log: { _ in })
    fatalError("Symlink followed")
} catch {}
precondition(try Data(contentsOf: test) == payload)
print("ACCESS FIXTURES PASS")
'''
# Swift precondition autoclosure is nonthrowing.
tests = tests.replace('precondition(try Data(contentsOf: test) == payload)',
                      'let readINDEX = try Data(contentsOf: test); precondition(readINDEX == payload)',1)
tests = tests.replace('readINDEX','read1')
tests = tests.replace('precondition(try Data(contentsOf: test) == payload)',
                      'let read2 = try Data(contentsOf: test); precondition(read2 == payload)')
prefix = '''import Foundation
import Darwin
enum PosterBoardStore {
    static func failure(_ s: String) -> NSError {
        NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: s])
    }
}
enum ProbeWriteTest {
'''
Path("/tmp/pb-access-fixtures.swift").write_text(prefix + body + tests)
