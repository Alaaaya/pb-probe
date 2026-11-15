import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct PBProbeApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

@MainActor
final class ProbeModel: ObservableObject {
    @Published var log = "PB Probe · READ-ONLY ANIME ABSENCE v12 · standalone diagnostic\nDiagnose does not write PosterBoard. Access acquisition temporarily swaps this app's own group Caches, consumes an exact-path token, then restores Caches immediately.\n"
    @Published var container = ""
    @Published var archive: URL?
    @Published var busy = false
    @Published var importError: String?
    
    func append(_ text: String) {
        log += text + (text.hasSuffix("\n") ? "" : "\n")
        if log.utf8.count > 256_000 {
            log = "LOG DISPLAY bounded to newest 160k characters\n" + String(log.suffix(160_000))
        }
    }
    func run(apply: Bool, install: Bool = false, audit: Bool = false, cleanup: Bool = false, absence: Bool = false) {
        guard !apply && !install && !cleanup else {
            append("RESULT BLOCKED · writes disabled in this read-only diagnostic build. Journal preserved.")
            return
        }
        guard !busy else { return }
        busy = true
        let entered = container
        let selectedArchive = archive
        append("\n\(absence ? "READ-ONLY ANIME ABSENCE" : "SESSION")\n\(cleanup ? "OWNED ANIME CLEANUP" : (install ? "INSTALL TEST" : (apply ? "ACCESS TEST" : "DIAGNOSE"))) · \(Date()) · rule=Strict\niOS \(UIDevice.current.systemVersion) · bundle \(Bundle.main.bundleIdentifier ?? "?")")
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
                    if absence {
                        try ProbeAnimeAbsenceDiagnostic.run(path: path, log: logger)
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
                    return path

                }.value
                logBuffer.flush()
                if absence { append("RESULT ABSENCE DIAGNOSTIC COMPLETE · read the AUDIT ABSENCE observations, not proof of cleanup. Journal unchanged; no removal/install/refresh performed. Copy Log and stop.") }
                if audit { append("RESULT AUDIT PASS · bounded read-only observation finished and lease closed. Missing/denied observations remain inconclusive. No wallpaper installation or visibility proof.") }
                container = path
                // Terminal result is emitted on the UI actor, outside log backpressure.
                if cleanup { append("RESULT OWNED CLEANUP PASS · exact prior Anime test descriptor removed and matching pending marker archived; all evidence retained. No other wallpaper/index/preferences changed. No reinstall or refresh performed.") }
                if !audit && !cleanup && !absence { append(install ? "RESULT COPY PASS · approved wallpaper copied with three normalized identity fields and read back; lease closed. Gallery visibility and activation UNVERIFIED. Existing wallpapers/preferences untouched." : (apply
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
        guard !busy else { return }
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
    private let acid = Color(red: 0.73, green: 0.98, blue: 0.31)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("PB PROBE").font(.system(size: 27, weight: .black, design: .monospaced))
                Spacer()
                Text(model.busy ? "BUSY" : "READY").font(.caption.monospaced().bold()).foregroundStyle(acid)
            }
            Text("READ-ONLY / EXACT PRIOR ANIME").font(.caption2.monospaced()).foregroundStyle(.gray)
            TextField("Container path (blank = discover)", text: $model.container)
                .font(.caption.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(10).background(.white.opacity(0.07))
                .disabled(model.busy)
            Text("STRICT IDENTITY · installation and removal DISABLED").font(.caption2.monospaced()).foregroundStyle(.gray)
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
            Button("Remove Prior Anime Test", role: .destructive) { confirmCleanup = true }
                .buttonStyle(.bordered).font(.caption.bold()).disabled(true)
            HStack {
                Text("SESSION LOG").font(.caption2.monospaced().bold()).foregroundStyle(.gray)
                Spacer()
                Button("Copy Log") { UIPasteboard.general.string = model.log }.font(.caption.bold()).tint(acid)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(model.log).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
            }.background(.black).overlay(Rectangle().stroke(.white.opacity(0.15)))
            Text("READ-ONLY diagnostic, device-untested. Check Prior Anime reads the exact historical path and reports syscall errors. No deletion, installation, journal clearing, preferences/index edits or refresh. Copy Log and stop. Access acquisition still temporarily swaps and restores this app’s own group Caches.")
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
        .alert("Remove ONLY the prior Anime test?", isPresented: $confirmCleanup) {
            Button("Cancel", role: .cancel) {}
            Button("Remove Prior Anime Test", role: .destructive) { model.run(apply: false, cleanup: true) }
        } message: {
            Text("Deletes ONLY the old Anime test copy BE2EE206 in CollectionsPoster store 61, with the exact matching B6DDAE7B journal. Its full original file manifest, journal and container identity must match or removal stops. A verified backup and all journal evidence stay in Files. Other wallpapers, preferences and gallery indexes are untouched. No reset, refresh, or reinstall. This is device-untested. After this step, Copy Log and stop. Continue?")
        }
        .alert("Run temporary access test?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Test Access") { model.run(apply: true) }
        } message: {
            Text("Only after strict identity checks, create one unique temporary test file in the existing PosterBoard datastore root, verify its bytes, then remove only that file. No wallpaper is installed. A journal is saved in Files. If interrupted, the log identifies any leftover test file.")
        }
    }
}
