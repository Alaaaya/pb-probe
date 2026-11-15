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
assert 'guard !apply && !cleanup else' in app
assert app.index('try ProbeAnimeJournalReconcile.run') < app.index('reconciled = true')
assert 'Button("Reconcile Journal")' in app
assert '.disabled(model.busy || !model.reconciled)' in app
assert 'guard !install || reconciled else' in app
assert 'if reconcile || install { reconciled = false }' in app
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

// Generalized actual-source journal selection and scope validation.
let selection = base.appendingPathComponent("selection")
let journalID = "A222B888-1111-4111-8111-111111111111"
let descriptor = "43E29B4A-89D5-4918-A641-EC162016FC8B"
let selectedJournal = selection.appendingPathComponent("InstallTests").appendingPathComponent(journalID)
try fm.createDirectory(at: selectedJournal, withIntermediateDirectories: true)
let changed = ["com.apple.posterkit.provider.descriptor.identifier",
    "versions/1/contents/com.apple.posterkit.provider.contents.userInfo",
    "versions/1/contents/7400.WWDC_2022-390w-844h@3x~iphone.wallpaper/Wallpaper.plist"]
var normalized = ApprovedAnimeManifest.files
for name in changed { normalized[name] = String(repeating: "a", count: 64) }
var record: [String: Any] = ["container": "/var/mobile/Containers/Data/Application/11111111-1111-4111-8111-111111111111",
    "relative": ProbeOwnedAnimeCleanup.parentRelative + "/" + descriptor,
    "archiveSHA256": ProbeInstallTest.approvedSHA256, "sourceIdentifier": "7400", "normalizedIdentifier": 60527,
    "normalizedFiles": changed, "originalManifest": ApprovedAnimeManifest.files, "expected": normalized,
    "existingFilesModified": false, "preferencesModified": false, "registrationIPC": false, "galleryVerified": false]
let container = record["container"] as! String
let recordBytes = try JSONSerialization.data(withJSONObject: record)
try recordBytes.write(to: selectedJournal.appendingPathComponent("pending.json"))
let selectedID = try ProbeAnimeJournalReconcile.pendingJournal(documents: selection)
precondition(selectedID == journalID)
let scope = try ProbeAnimeJournalReconcile.Scope(journalID: journalID, record: recordBytes, path: container)
precondition(scope.descriptor == descriptor)
let selectedLocal = try ProbeAnimeJournalReconcile.LocalJournal(documents: selection, journalID: selectedID)
precondition(selectedLocal.record == recordBytes)
record["relative"] = ProbeOwnedAnimeCleanup.parentRelative + "/../other"
refuse("escaped descriptor scope") { _ = try ProbeAnimeJournalReconcile.Scope(journalID: journalID,
    record: JSONSerialization.data(withJSONObject: record), path: container) }
record["relative"] = ProbeOwnedAnimeCleanup.parentRelative + "/" + descriptor
record["originalManifest"] = ["wrong": "manifest"]
refuse("foreign manifest") { _ = try ProbeAnimeJournalReconcile.Scope(journalID: journalID,
    record: JSONSerialization.data(withJSONObject: record), path: container) }
let secondJournal = selectedJournal.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
try fm.createDirectory(at: secondJournal, withIntermediateDirectories: false)
try recordBytes.write(to: secondJournal.appendingPathComponent("pending.json"))
refuse("multiple pending journals") { _ = try ProbeAnimeJournalReconcile.pendingJournal(documents: selection) }
let presence = base.appendingPathComponent("present-descriptor")
try fm.createDirectory(at: presence.appendingPathComponent(descriptor), withIntermediateDirectories: true)
precondition(ProbeAnimeAbsenceDiagnostic.observe(parent: presence, name: descriptor, log: { _ in }) == "PRESENT_MATCHING_DIRECTORY")
precondition(fm.fileExists(atPath: selectedJournal.appendingPathComponent("pending.json").path))
print("GENERALIZED JOURNAL SCOPE FIXTURES PASS recorded-uuid/normalized-manifest/selection/foreign-refusal/multiple-refusal/present-keeps-pending")

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
