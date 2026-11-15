from pathlib import Path
s = Path('Sources/ProbeAnimeAbsenceDiagnostic.swift').read_text()
for forbidden in ['.write(', 'createDirectory', 'copyItem', 'removeItem', 'unlink(', 'unlinkat(', 'mkdir(', 'O_CREAT', 'O_WRONLY', 'moveItem', 'Tree(', 'removeVerified(', 'writeEvidence(']:
    assert forbidden not in s, forbidden
app = Path('Sources/PBProbeApp.swift').read_text()
assert 'guard !apply && !cleanup && !install && !reconcile else' in app
assert app.index('guard !apply && !cleanup && !install && !reconcile else') < app.index('guard !busy')
assert 'Button("Check Prior Anime")' in app
assert '}.buttonStyle(.bordered).tint(acid).font(.caption.bold()).disabled(model.busy)' in app
assert 'ProbeAnimeAbsenceDiagnostic.run' in app
assert 'pending journal byte-identical' in s
start = s.index('    @discardableResult')
fixture = 'import Foundation\nimport Darwin\nenum ProbeAnimeAbsenceDiagnostic {\n' + s[start:]
fixture += r'''
let fm = FileManager.default
let base = fm.temporaryDirectory.appendingPathComponent("pb-absence-" + UUID().uuidString)
try fm.createDirectory(at: base, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: base) }
var lines = [String]()
func observe(_ parent: URL, _ name: String) -> String {
    lines = []
    return ProbeAnimeAbsenceDiagnostic.observe(parent: parent, name: name) { lines.append($0) }
}
precondition(observe(base, "missing") == "ENOENT_OBSERVED_EXACT_PATH")
precondition(lines.contains { $0.contains("openat(") && $0.contains("errno=2 ") })
precondition(lines.contains { $0.contains("fstatat(parentFD") && $0.contains("errno=2 ") })
precondition(lines.contains { $0.contains("open(exactAbsoluteRoot)") && $0.contains("errno=2 ") })
try fm.createDirectory(at: base.appendingPathComponent("present"), withIntermediateDirectories: false)
precondition(observe(base, "present") == "PRESENT_MATCHING_DIRECTORY")
if geteuid() != 0 {
    precondition(chmod(base.appendingPathComponent("present").path, 0) == 0)
    precondition(observe(base, "present") == "INCONCLUSIVE_OR_PATH_ERROR")
    precondition(lines.contains { $0.contains("errno=13 ") })
    precondition(chmod(base.appendingPathComponent("present").path, 0o700) == 0)
}
try fm.createSymbolicLink(atPath: base.appendingPathComponent("link").path, withDestinationPath: "present")
precondition(observe(base, "link") == "INCONCLUSIVE_OR_PATH_ERROR")
try Data("untouched".utf8).write(to: base.appendingPathComponent("regular"))
precondition(observe(base, "regular") == "INCONCLUSIVE_OR_PATH_ERROR")
precondition(try String(contentsOf: base.appendingPathComponent("regular")) == "untouched")
precondition(observe(base.appendingPathComponent("missingParent"), "entry") == "INCONCLUSIVE_OR_PATH_ERROR")
try fm.createSymbolicLink(atPath: base.appendingPathComponent("parentLink").path, withDestinationPath: base.path)
precondition(observe(base.appendingPathComponent("parentLink"), "missing") == "INCONCLUSIVE_OR_PATH_ERROR")
precondition(Set(try fm.contentsOfDirectory(atPath: base.path)) == Set(["present", "link", "regular", "parentLink"]))
print("READONLY ABSENCE SYSCALL FIXTURES PASS missing/present/symlink/file/missing-parent/redirected-parent unchanged")
'''
# Swift precondition autoclosures cannot throw.
fixture = fixture.replace('precondition(try String(contentsOf: base.appendingPathComponent("regular")) == "untouched")', 'let contents = try String(contentsOf: base.appendingPathComponent("regular"))\nprecondition(contents == "untouched")')
fixture = fixture.replace('precondition(Set(try fm.contentsOfDirectory(atPath: base.path)) ==', 'let entries = try fm.contentsOfDirectory(atPath: base.path)\nprecondition(Set(entries) ==')
Path('/tmp/pb-absence-fixtures.swift').write_text(fixture)
print('READONLY ABSENCE SOURCE BOUNDS PASS; actual-source Swift syscall fixture generated')
