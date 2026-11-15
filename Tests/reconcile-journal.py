"""Compile and execute actual local transaction + absence syscalls on macOS."""
from pathlib import Path
import runpy
parts = runpy.run_path("Tests/owned-cleanup.py")
source = Path("Sources/ProbeAnimeJournalReconcile.swift").read_text()
diagnostic = Path("Sources/ProbeAnimeAbsenceDiagnostic.swift").read_text()
app = Path("Sources/PBProbeApp.swift").read_text()
for forbidden in ["unlink(", "unlinkat(", "removeItem(", "Tree(", "removeVerified(", "UserDefaults", "resetProtections", "lease.grant("]:
    assert forbidden not in source, forbidden
assert 'requireAbsence: true' in source
assert source.index('requireAbsence: true') < source.index('try local.archiveMarker(evidence: evidence)')
assert diagnostic.index('try lease.close()') < diagnostic.index('return transcript')
assert 'try local.validate()' in source
assert 'UInt32(RENAME_EXCL)' in source
assert 'guard !apply && !cleanup && !reconcile else' in app
assert app.index('try ProbeAnimeJournalReconcile.run') < app.index('reconciled = true')
assert 'Button("Reconcile Journal")' in app
assert '.disabled(true)' in app
assert 'else if install {' in app
# Both the unmodified original cleanup helpers and new local transaction compile.
fixture = parts["stub"] + Path("Sources/ApprovedAnimeManifest.swift").read_text() + parts["s"] + diagnostic + source
fixture += r'''
let fm = FileManager.default
let base = fm.temporaryDirectory.appendingPathComponent("pb-reconcile-" + UUID().uuidString)
try fm.createDirectory(at: base, withIntermediateDirectories: false)
defer { try? fm.removeItem(at: base) }
func refuse(_ label: String, _ action: () throws -> Void) {
    do { try action(); fatalError("accepted unsafe " + label) } catch {}
}
func setup(_ name: String) throws -> (URL, URL) {
    let docs = base.appendingPathComponent(name)
    let journal = docs.appendingPathComponent("InstallTests").appendingPathComponent(ProbeOwnedAnimeCleanup.journalID)
    try fm.createDirectory(at: journal, withIntermediateDirectories: true)
    try Data("exact historical bytes".utf8).write(to: journal.appendingPathComponent("pending.json"))
    try Data("original preserved".utf8).write(to: journal.appendingPathComponent("original.tendies"))
    return (docs, journal)
}
let (docs, journal) = try setup("success")
let local = try ProbeAnimeJournalReconcile.LocalJournal(documents: docs)
let evidence = try local.prepareEvidence(path: "fixture-only")
refuse("missing absence proof") { try local.archiveMarker(evidence: evidence) }
try ProbeOwnedAnimeCleanup.writeEvidence(Data(("AUDIT ABSENCE CLASSIFICATION ENOENT_OBSERVED_EXACT_PATH\n" + "AUDIT ABSENCE CLASSIFICATION ENOENT_OBSERVED_EXACT_PATH\n" + "AUDIT ABSENCE COMPLETE · lease closed; pending journal byte-identical").utf8),
    to: evidence.appendingPathComponent("absence-lease-closed.txt"))
try local.archiveMarker(evidence: evidence)
let archived = try Data(contentsOf: journal.appendingPathComponent(ProbeAnimeJournalReconcile.archivedName))
precondition(archived == local.record)
precondition(!fm.fileExists(atPath: journal.appendingPathComponent("pending.json").path))
let original = try String(contentsOf: journal.appendingPathComponent("original.tendies"))
precondition(original == "original preserved")
let evidenceRecord = try Data(contentsOf: evidence.appendingPathComponent("pending-original.json"))
precondition(evidenceRecord == local.record)
precondition(fm.fileExists(atPath: evidence.appendingPathComponent("proof.json").path))
refuse("repeat reconcile") { _ = try ProbeAnimeJournalReconcile.LocalJournal(documents: docs) }
let (mutDocs, mutJournal) = try setup("mutated")
let mutated = try ProbeAnimeJournalReconcile.LocalJournal(documents: mutDocs)
try Data("CHANGED".utf8).write(to: mutJournal.appendingPathComponent("pending.json"))
refuse("changed pending bytes") { try mutated.archiveMarker(evidence: evidence) }
precondition(fm.fileExists(atPath: mutJournal.appendingPathComponent("pending.json").path))
let (replaceDocs, replaceJournal) = try setup("replaced")
let replaced = try ProbeAnimeJournalReconcile.LocalJournal(documents: replaceDocs)
try fm.moveItem(at: replaceJournal.appendingPathComponent("pending.json"), to: replaceJournal.appendingPathComponent("saved.json"))
try replaced.record.write(to: replaceJournal.appendingPathComponent("pending.json"))
refuse("same bytes different inode") { try replaced.archiveMarker(evidence: evidence) }
let (linkDocs, linkJournal) = try setup("linked")
try fm.moveItem(at: linkJournal.appendingPathComponent("pending.json"), to: linkJournal.appendingPathComponent("target.json"))
try fm.createSymbolicLink(atPath: linkJournal.appendingPathComponent("pending.json").path, withDestinationPath: "target.json")
refuse("symlink pending") { _ = try ProbeAnimeJournalReconcile.LocalJournal(documents: linkDocs) }
let (hardDocs, hardJournal) = try setup("hardlinked")
try fm.linkItem(at: hardJournal.appendingPathComponent("pending.json"), to: hardJournal.appendingPathComponent("second-link"))
refuse("hardlinked pending") { _ = try ProbeAnimeJournalReconcile.LocalJournal(documents: hardDocs) }
let (collisionDocs, collisionJournal) = try setup("collision")
let collision = try ProbeAnimeJournalReconcile.LocalJournal(documents: collisionDocs)
try Data("archive stays".utf8).write(to: collisionJournal.appendingPathComponent(ProbeAnimeJournalReconcile.archivedName))
refuse("existing archive") { try collision.archiveMarker(evidence: evidence) }
let collisionBytes = try String(contentsOf: collisionJournal.appendingPathComponent(ProbeAnimeJournalReconcile.archivedName))
precondition(collisionBytes == "archive stays")
let (danglingDocs, danglingJournal) = try setup("dangling")
let dangling = try ProbeAnimeJournalReconcile.LocalJournal(documents: danglingDocs)
try fm.createSymbolicLink(atPath: danglingJournal.appendingPathComponent(ProbeAnimeJournalReconcile.archivedName).path,
    withDestinationPath: "missing")
refuse("dangling archive") { try dangling.archiveMarker(evidence: evidence) }
let (moveDocs, moveJournal) = try setup("moved")
let moved = try ProbeAnimeJournalReconcile.LocalJournal(documents: moveDocs)
try fm.moveItem(at: moveJournal, to: moveJournal.deletingLastPathComponent().appendingPathComponent("moved-away"))
try fm.createDirectory(at: moveJournal, withIntermediateDirectories: false)
try moved.record.write(to: moveJournal.appendingPathComponent("pending.json"))
refuse("journal directory replaced") { try moved.archiveMarker(evidence: evidence) }
let (deniedDocs, deniedJournal) = try setup("proof-failure")
let denied = try ProbeAnimeJournalReconcile.LocalJournal(documents: deniedDocs)
if geteuid() != 0 {
    precondition(chmod(deniedJournal.path, 0o500) == 0)
    refuse("evidence creation denied") { _ = try denied.prepareEvidence(path: "fixture-only") }
    precondition(chmod(deniedJournal.path, 0o700) == 0)
}
precondition(fm.fileExists(atPath: deniedJournal.appendingPathComponent("pending.json").path))
// Actual diagnostic classifications refuse permission/presence/redirects.
// Inject entry and parent races using its existing log callback, not device hooks.
let observed = base.appendingPathComponent("observed")
try fm.createDirectory(at: observed, withIntermediateDirectories: false)
var inserted = false
let entryRace = ProbeAnimeAbsenceDiagnostic.observe(parent: observed, name: "old") { line in
    if !inserted && line.contains("lstat(parent, final) rc=") {
        inserted = true
        try! fm.createDirectory(at: observed.appendingPathComponent("old"), withIntermediateDirectories: false)
    }
}
precondition(entryRace != "ENOENT_OBSERVED_EXACT_PATH")
try fm.removeItem(at: observed.appendingPathComponent("old"))
var redirected = false
let parentRace = ProbeAnimeAbsenceDiagnostic.observe(parent: observed, name: "old") { line in
    if !redirected && line.contains("open(exactAbsoluteRoot)") {
        redirected = true
        try! fm.moveItem(at: observed, to: base.appendingPathComponent("observed-held"))
        try! fm.createDirectory(at: observed, withIntermediateDirectories: false)
    }
}
precondition(parentRace != "ENOENT_OBSERVED_EXACT_PATH")
print("EXACT JOURNAL RECONCILE FIXTURES PASS archive/evidence/unchanged-original/repeat/bytes/inode/symlink/hardlink/collision/dangling/redirect/proof-failure/entry-race/parent-race")
'''
Path("/tmp/pb-reconcile-fixtures.swift").write_text(fixture)
print("EXACT JOURNAL RECONCILE SOURCE BOUNDS PASS; actual-source Swift fixtures generated")
