from pathlib import Path
s = Path("Sources/ProbeWriteTest.swift").read_text()
run = s[:s.index("    static func exclusiveRoundTrip")]
assert "PosterBoardStore.layout(" not in run
assert "contentsOfDirectory" not in run
assert "/Extensions" not in run
assert "layout.version" not in run
assert 'let relative = "Library/Application Support/PRBPosterExtensionDataStore"' in run
assert "O_EXCL" in s and "O_NOFOLLOW" in s
assert "current.st_ino == owned.st_ino" in s
app = Path("Sources/PBProbeApp.swift").read_text()
assert 'append(install' in app and "RESULT PASS" in app and "RESULT ERROR" in app
buffer = Path("Sources/ProbeLogBuffer.swift").read_text()
fixture = r'''
final class Box: @unchecked Sendable { var text = "" }
let box = Box()
let buffer = ProbeLogBuffer { box.text += $0 }
for _ in 0..<2000 { buffer.submit(String(repeating: "checkpoint", count: 20)) }
buffer.submit("TEST readback exact bytes PASS")
buffer.submit("TEST cleanup verified")
buffer.submit("ACCESS TEST COMPLETE")
buffer.flush()
precondition(box.text.contains("LOG BACKPRESSURE"))
for marker in ["TEST readback exact bytes PASS", "TEST cleanup verified", "ACCESS TEST COMPLETE"] {
    precondition(box.text.contains(marker))
}
let previous = box.text
buffer.flush()
precondition(box.text == previous)
print("BOUNDED ACCESS AND BACKPRESSURE PASS")
'''
Path("/tmp/pb-buffer-fixture.swift").write_text(buffer + fixture)
print("PASS bounded access source regression; Swift buffer fixture generated")
