import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct PBProbeApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

@MainActor
final class ProbeModel: ObservableObject {
    @Published var log = "PB Probe · READ-ONLY PLACARD COMPARISON v14 · standalone diagnostic\nDiagnose does not write PosterBoard. Access acquisition temporarily swaps this app's own group Caches, consumes an exact-path token, then restores Caches immediately.\n"
    @Published var container = ""
    @Published var archive: URL?
    @Published var busy = false
    @Published var reconciled = false
    @Published var importError: String?
    
    func append(_ text: String) {
        log += text + (text.hasSuffix("\n") ? "" : "\n")
        if log.utf8.count > 4_000_000 {
            log = "LOG INCOMPLETE · bounded to newest 3M characters; missing sections must not be treated as absent\n" + String(log.suffix(3_000_000))
        }
    }
    func run(apply: Bool, install: Bool = false, audit: Bool = false, cleanup: Bool = false, absence: Bool = false, reconcile: Bool = false, compare: Bool = false) {
        guard !apply && !cleanup && !install && !reconcile else {
            append("RESULT BLOCKED · this comparison build disables all write/install/removal/reconciliation actions.")
            return
        }
        guard !busy else { return }
        busy = true
        let entered = container
        let selectedArchive = archive
        append("\n\(reconcile ? "EXACT JOURNAL RECONCILIATION" : (absence ? "READ-ONLY ANIME ABSENCE" : "SESSION"))\n\(cleanup ? "OWNED ANIME CLEANUP" : (install ? "INSTALL TEST" : (apply ? "ACCESS TEST" : "DIAGNOSE"))) · \(Date()) · rule=Strict\niOS \(UIDevice.current.systemVersion) · bundle \(Bundle.main.bundleIdentifier ?? "?")")
        if compare { log = "PB Probe · READ-ONLY PLACARD COMPARISON v14\n" }
        let logBuffer = ProbeLogBuffer { [weak self] batch in
            MainActor.assumeIsolated { self?.append(batch) }
        }
        let logger: (String) -> Void = { logBuffer.submit($0) }
        let stallNotice = Task {
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled, busy else { return }
            append("WATCHDOG · diagnostic still running. Synchronous OS calls cannot safely be force-cancelled during a Caches swap. Batched UI logs may lag; the last displayed checkpoint is not proof that a call hung. No PosterBoard access success is implied; do not start a concurrent run.")
        }
        Task {
            defer { stallNotice.cancel() }
            do {
                let path = try await Task.detached(priority: .userInitiated) {
                    let progress = ProbeProgress(logger)
                    defer { progress.finish(); withExtendedLifetime(progress) {} }
                    logger("WORKER BEFORE discovery/canonical path")
                    let path = entered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? try ProbeDiagnostics.discover(log: logger)
                        : try PosterBoardStore.canonicalContainer(entered)
                    guard try ProbeDiagnostics.identifiesPosterBoard(path, log: logger) else {
                        throw PosterBoardStore.failure("Exact metadata did not identify PosterBoard. No root inspection performed.")
                    }
                    var comparisonReport: String?
                    if compare {
                        comparisonReport = try ProbePlacardComparison.run(path: path, log: logger)
                    } else if reconcile {
                        try ProbeAnimeJournalReconcile.run(path: path, log: logger)
                    } else if absence {
                        _ = try ProbeAnimeAbsenceDiagnostic.run(path: path, log: logger)
                    } else if cleanup {
                        try ProbeOwnedAnimeCleanup.run(path: path, log: logger)
                    } else if audit {
                        try ProbeGalleryAudit.run(path: path, log: logger)
                    } else if install {
                        guard let selectedArchive else { throw PosterBoardStore.failure("Import the approved Anime-Squad.tendies first.") }
                        try ProbeInstallTest.run(path: path, archive: selectedArchive, log: logger)
                    } else if apply {
                        try ProbeWriteTest.run(path: path, log: logger)
                    } else {
                        logger("DIAGNOSE COMPLETE · PosterBoard metadata identity verified; no root inspection or writes.")
                    }
                    return (path, comparisonReport)

                }.value
                logBuffer.flush()
                if let report = path.1 { append(report) }
                if absence { append("RESULT ABSENCE DIAGNOSTIC COMPLETE · read the AUDIT ABSENCE observations, not proof of cleanup. Journal unchanged; no removal/install/refresh performed. Copy Log and stop.") }
                if audit { append("RESULT AUDIT PASS · bounded read-only observation finished and lease closed. Missing/denied observations remain inconclusive. No wallpaper installation or visibility proof.") }
                if reconcile {
                    reconciled = true
                    append("RESULT JOURNAL RECONCILE PASS · only own-app historical pending marker archived. No wallpaper installed or deleted. Copy Log and stop before a separate parity test.")
                }
                container = path.0
                // Terminal result is emitted on the UI actor, outside log backpressure.
                if cleanup { append("RESULT OWNED CLEANUP PASS · exact prior Anime test descriptor removed and matching pending marker archived; all evidence retained. No other wallpaper/index/preferences changed. No reinstall or refresh performed.") }
                if !audit && !cleanup && !absence && !reconcile && !compare { append(install ? "RESULT COPY PASS · approved wallpaper copied with three normalized identity fields and read back; lease closed. Gallery visibility and activation UNVERIFIED. Existing wallpapers/preferences untouched." : (apply
                    ? "RESULT PASS · exclusive sentinel create/write/readback/ownership-checked removal and lease close completed. No wallpaper installed."
                    : "RESULT PASS · strict metadata identity verified only. No PosterBoard writes.")) }
            } catch {
                logBuffer.flush()
                append("RESULT ERROR · \(ProbeDiagnostics.describe(error)) · operation not confirmed successful. Preserve the session log and InstallTests journal; do not retry blindly.")
            }
            busy = false
        }
    }
    func importFile(_ url: URL) {
        guard !busy && false else { return }
        append("PICKER URL received · name=\(url.lastPathComponent) extension=\(url.pathExtension) isFileURL=\(url.isFileURL)")
        guard url.pathExtension.lowercased() == "tendies" else {
            importError = "Selected \(url.lastPathComponent). Choose a .tendies wallpaper file."
            append("IMPORT ERROR · " + (importError ?? "Invalid file"))
            return
        }
        busy = true
        Task {
            do {
                let saved = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    DispatchQueue.main.async {
                        self.append("IMPORT security scope=\(scoped); false can be normal for an import-as-copy URL already inside our sandbox.")
                    }
                    let fm = FileManager.default
                    let folder = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Imports")
                    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                    let destination = folder.appendingPathComponent(UUID().uuidString + ".tendies")
                    var coordinationError: NSError?
                    var copyError: Error?
                    var copied = false
                    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
                        do {
                            let values = try readable.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentTypeKey])
                            guard values.isRegularFile == true else {
                                throw PosterBoardStore.failure("Selection is not a regular wallpaper file.")
                            }
                            DispatchQueue.main.async {
                                self.append("IMPORT coordinated read · bytes=\(values.fileSize ?? -1) type=\(values.contentType?.identifier ?? "<unknown>")")
                            }
                            try fm.copyItem(at: readable, to: destination)
                            copied = true
                        } catch { copyError = error }
                    }
                    if let coordinationError { throw coordinationError }
                    if let copyError { throw copyError }
                    guard copied else { throw PosterBoardStore.failure("File provider did not supply readable content.") }
                    do { try TendiesArchive().validateArchive(destination) }
                    catch { try? fm.removeItem(at: destination); throw error }
                    return destination
                }.value
                archive = saved
                append("IMPORTED · \(url.lastPathComponent), validated ZIP.")
            } catch {
                importError = ProbeDiagnostics.describe(error)
                append("IMPORT ERROR · " + (importError ?? "Unknown error"))
            }
            busy = false
        }
    }
}

struct ProbeView: View {
    @StateObject private var model = ProbeModel()
    @State private var picker = false
    @State private var confirm = false
    @State private var confirmInstall = false
    @State private var confirmCleanup = false
    @State private var confirmReconcile = false
    private let acid = Color(red: 0.73, green: 0.98, blue: 0.31)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("PB PROBE").font(.system(size: 27, weight: .black, design: .monospaced))
                Spacer()
                Text(model.busy ? "BUSY" : "READY").font(.caption.monospaced().bold()).foregroundStyle(acid)
            }
            Text("PLACARD vs PROBE / READ ONLY").font(.caption2.monospaced()).foregroundStyle(.gray)
            TextField("Container path (blank = discover)", text: $model.container)
                .font(.caption.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(10).background(.white.opacity(0.07))
                .disabled(model.busy)
            Text("STRICT IDENTITY · all install/removal/reconciliation DISABLED").font(.caption2.monospaced()).foregroundStyle(.gray)
            HStack(spacing: 8) {
                Button("Import .tendies") {
                    model.append("PICKER requested")
                    picker = true
                }.disabled(true)
                Button("Diagnose") { model.run(apply: false) }
                Button("Check Prior Anime") { model.run(apply: false, absence: true) }
            }.buttonStyle(.bordered).tint(acid).font(.caption.bold()).disabled(model.busy)
            if model.archive != nil {
                Button("Test Install") { confirmInstall = true }
                    .buttonStyle(.bordered).tint(acid).disabled(true)
                Text("APPROVED ARCHIVE REQUIRED · no preference edits or respring").font(.caption2.monospaced()).foregroundStyle(acid) }
            Button("Compare With Placard") { model.run(apply: false, compare: true) }
                .buttonStyle(.borderedProminent).tint(acid).font(.caption.bold()).disabled(model.busy)
            Button("Reconcile Prior Anime Journal") { confirmReconcile = true }
                .buttonStyle(.bordered).tint(acid).font(.caption.bold()).disabled(true)
            HStack {
                Text("SESSION LOG").font(.caption2.monospaced().bold()).foregroundStyle(.gray)
                Spacer()
                Button("Copy Log") { UIPasteboard.general.string = model.log }.font(.caption.bold()).tint(acid)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(model.log).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
            }.background(.black).overlay(Rectangle().stroke(.white.opacity(0.15)))
            Text("Device-untested. Compare With Placard only reads store 61 through existing bounded grants. Lists siblings, compares Anime content candidates, prints full structured metadata and matching indexes. Provenance and gallery visibility remain unverified. All writes and imports disabled. Press Compare once, wait, then Copy Log and stop.")
                .font(.caption2).foregroundStyle(.gray)
        }
        .padding(16).background(Color(white: 0.065)).foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $picker) {
            AnyFilePicker(selected: { url in
                picker = false
                model.importFile(url)
            }, cancelled: {
                picker = false
            }, trace: { text in
                DispatchQueue.main.async { model.append(text) }
            })
        }
        .alert("Import failed", isPresented: Binding(
            get: { model.importError != nil && !picker },
            set: { if !$0 { model.importError = nil } }
        )) {
            Button("OK") { model.importError = nil }
        } message: {
            Text(model.importError ?? "See session log.")
        }
        .alert("Add the approved wallpaper?", isPresented: $confirmInstall) {
            Button("Cancel", role: .cancel) {}
            Button("Test Install") { model.run(apply: false, install: true) }
        } message: {
            Text("Copies one approved Anime-Squad descriptor with archived file attributes, three normalized numeric identity fields and whole-root copy. Prior test journal or duplicate blocks the test and is never deleted. Existing wallpapers and preferences stay unchanged. No automatic activation, registration call, reset or respring. This is untested and the wallpaper picker may fail. If interrupted, preserve the InstallTests journal and do not retry. Continue?")
        }
        .alert("Archive ONLY the old test journal marker?", isPresented: $confirmReconcile) {
            Button("Cancel", role: .cancel) {}
            Button("Reconcile Journal") { model.run(apply: false, reconcile: true) }
        } message: {
            Text("Rechecks that the exact prior Anime BE2EE206 is absent in store 61. If present, denied, redirected or uncertain, stops and keeps pending. Only this app's B6DDAE7B pending marker is archived, with original journal, archive and absence proof retained. No wallpaper files are deleted or written. No indexes, preferences, reset or refresh. Installation does NOT run automatically. After success, Copy Log and stop. Continue?")
        }
        .alert("Run temporary access test?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Test Access") { model.run(apply: true) }
        } message: {
            Text("Only after strict identity checks, create one unique temporary test file in the existing PosterBoard datastore root, verify its bytes, then remove only that file. No wallpaper is installed. A journal is saved in Files. If interrupted, the log identifies any leftover test file.")
        }
    }
}
