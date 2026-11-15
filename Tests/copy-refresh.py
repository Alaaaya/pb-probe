"""Generate actual-source Swift gate/evidence tests. Never execute the stress page."""
from pathlib import Path
import re, subprocess, tempfile
app = Path('Sources/PBProbeApp.swift').read_text()
view = Path('Sources/ProbeRespringView.swift').read_text()
source = Path('Sources/ProbeRefreshGate.swift').read_text()
assert app.index('try ProbeInstallTest.run') < app.index('refreshGate.copyFinished(success: true)')
assert app.index('refreshGate.copyFinished(success: true)') < app.index('showRefreshConfirmation = true')
decide = app[app.index('func decideRefresh'):app.index('@Published var container')]
assert decide.index('try ProbeRefreshEvidence.record') < decide.index('showRespring = true')
assert 'guard busy == false, refreshGate.awaitingConfirmation else' in decide
assert 'guard !busy, !refreshGate.awaitingConfirmation, !refreshGate.running else' in app
assert 'Button("Skip respring", role: .cancel)' in app
assert 'Button("Respring now", role: .destructive)' in app
assert '.fullScreenCover(isPresented: $model.showRespring' in app
assert 'refreshGate.stop()' in app
assert 'webViewWebContentProcessDidTerminate' in view
assert '.nonPersistent()' in view and 'allowsContentJavaScript = true' in view
assert 'webView.reload' not in view
assert 'URLSession' not in view and 'addScriptMessageHandler' not in view
assert 'loadHTMLString(Self.document, baseURL: nil)' in view
assert 'REFRESH BEFORE' in view and 'REFRESH AFTER' in view
assert 'group.com.alaa.pbprobe' in Path('PBProbe.entitlements').read_text()
# Build/delivery must not mutate identity entitlements or old safety code.
assert 'guard !install || reconciled else' in app
assert 'if reconcile || install { reconciled = false }' in app
html = view.split('static let document = #"""',1)[1].split('"""#',1)[0]
assert '<meta charset="utf-8">' in html
js = html.split('<script>',1)[1].rsplit('</script>',1)[0]
assert 'https://' not in html and 'http://' not in html
# Parse only, DO NOT execute the intentionally disruptive payload.
with tempfile.NamedTemporaryFile(suffix='.js',mode='w') as f:
    f.write(js); f.flush()
    subprocess.run(['node','--check',f.name],check=True)
fixture = r'''
var gate = ProbeRefreshGate()
precondition(!gate.decide(confirmed: true))
gate.copyFinished(success: false)
precondition(!gate.decide(confirmed: true))
gate.copyFinished(success: true)
precondition(gate.awaitingConfirmation && !gate.running)
precondition(!gate.decide(confirmed: false))
precondition(!gate.decide(confirmed: true))
gate.copyFinished(success: true)
precondition(gate.decide(confirmed: true))
precondition(!gate.awaitingConfirmation && gate.running)
precondition(!gate.decide(confirmed: true))
gate.stop()
precondition(!gate.running && !gate.decide(confirmed: true))
let restarted = ProbeRefreshGate()
precondition(!restarted.running && !restarted.awaitingConfirmation)
let fm = FileManager.default
let directory = fm.temporaryDirectory.appendingPathComponent("refresh-fixture-" + UUID().uuidString)
try fm.createDirectory(at: directory, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: directory) }
try ProbeRefreshEvidence.record("REFRESH BEFORE fixture", documents: directory)
try ProbeRefreshEvidence.record("REFRESH AFTER fixture", documents: directory)
let file = directory.appendingPathComponent("LastRefreshAttempt.txt")
let text = try String(contentsOf: file, encoding: .utf8)
precondition(text.contains("REFRESH BEFORE fixture") && text.contains("REFRESH AFTER fixture"))
try Data(repeating: 65, count: 128_001).write(to: file)
var refused = false
do { try ProbeRefreshEvidence.record("must refuse full evidence", documents: directory) }
catch { refused = true }
precondition(refused)
precondition(try Data(contentsOf: file).count == 128_001)
print("COPY REFRESH ACTUAL GATE AND DURABLE EVIDENCE FIXTURES PASS")
'''
# precondition autoclosures cannot throw.
fixture = fixture.replace('precondition(try Data(contentsOf: file).count == 128_001)', 'let retained = try Data(contentsOf: file)\nprecondition(retained.count == 128_001)')
Path('/tmp/pb-copy-refresh-fixtures.swift').write_text(source + fixture)
print('COPY REFRESH SOURCE GATES AND JAVASCRIPT SYNTAX PASS; actual-source Swift fixtures generated')
