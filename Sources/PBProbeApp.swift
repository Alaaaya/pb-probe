import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct PBProbeApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

@MainActor
final class ProbeModel: ObservableObject {
    @Published var log = "PB Probe · isolated-install v8 · source Mirsa 1b16937\nDiagnose does not write PosterBoard. Access acquisition temporarily swaps this app's own group Caches, consumes an exact-path token, then restores Caches immediately.\n"
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
    func run(apply: Bool, install: Bool = false) {
        guard !busy else { return }
        busy = true
        let entered = container
        let selectedArchive = archive
        append("\n\(install ? "INSTALL TEST" : (apply ? "ACCESS TEST" : "DIAGNOSE")) · \(Date()) · rule=Strict\niOS \(UIDevice.current.systemVersion) · bundle \(Bundle.main.bundleIdentifier ?? "?")")
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
                    if install {
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
                container = path
                // Terminal result is emitted on the UI actor, outside log backpressure.
                append(install ? "RESULT COPY PASS · exact approved wallpaper files copied and read back; lease closed. Gallery visibility and activation UNVERIFIED. Existing wallpapers/preferences untouched." : (apply
                    ? "RESULT PASS · exclusive sentinel create/write/readback/ownership-checked removal and lease close completed. No wallpaper installed."
                    : "RESULT PASS · strict metadata identity verified only. No PosterBoard writes."))
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
    private let acid = Color(red: 0.73, green: 0.98, blue: 0.31)
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("PB PROBE").font(.system(size: 27, weight: .black, design: .monospaced))
                Spacer()
                Text(model.busy ? "BUSY" : "READY").font(.caption.monospaced().bold()).foregroundStyle(acid)
            }
            Text("POSTERBOARD / PLACARD-STYLE ACCESS").font(.caption2.monospaced()).foregroundStyle(.gray)
            TextField("Container path (blank = discover)", text: $model.container)
                .font(.caption.monospaced()).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(10).background(.white.opacity(0.07))
                .disabled(model.busy)
            Text("STRICT IDENTITY · separately confirmed copy-only installation").font(.caption2.monospaced()).foregroundStyle(.gray)
            HStack(spacing: 8) {
                Button("Import .tendies") {
                    model.append("PICKER requested")
                    picker = true
                }
                Button("Diagnose") { model.run(apply: false) }
                Button("Test Access") { confirm = true }
            }.buttonStyle(.bordered).tint(acid).font(.caption.bold()).disabled(model.busy)
            if model.archive != nil {
                Button("Test Install Anime-Squad") { confirmInstall = true }
                    .buttonStyle(.bordered).tint(acid).disabled(model.busy)
                Text("APPROVED ARCHIVE REQUIRED · no preference edits or respring").font(.caption2.monospaced()).foregroundStyle(acid) }
            HStack {
                Text("SESSION LOG").font(.caption2.monospaced().bold()).foregroundStyle(.gray)
                Spacer()
                Button("Copy Log") { UIPasteboard.general.string = model.log }.font(.caption.bold()).tint(acid)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(model.log).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
            }.background(.black).overlay(Rectangle().stroke(.white.opacity(0.15)))
            Text("Test Install adds one approved descriptor, without changing existing wallpapers or preferences. Open the wallpaper picker manually once afterwards. Copy PASS does not prove it is visible. Test Access remains temporary-file only.")
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
            Text("Adds exactly one unchanged Anime-Squad descriptor after strict identity and duplicate checks. Existing wallpapers and preferences stay unchanged. No automatic activation, registration call, reset or respring. This is untested and the wallpaper picker may fail. If interrupted, preserve the InstallTests journal and do not retry. Continue?")
        }
        .alert("Run temporary access test?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Test Access") { model.run(apply: true) }
        } message: {
            Text("Only after strict identity checks, create one unique temporary test file in the existing PosterBoard datastore root, verify its bytes, then remove only that file. No wallpaper is installed. A journal is saved in Files. If interrupted, the log identifies any leftover test file.")
        }
    }
}
