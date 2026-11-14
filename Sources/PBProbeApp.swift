import SwiftUI
import UniformTypeIdentifiers
import UIKit

@main
struct PBProbeApp: App {
    var body: some Scene { WindowGroup { ProbeView() } }
}

@MainActor
final class ProbeModel: ObservableObject {
    @Published var log = "PB Probe · native-picker v3 · source Mirsa 1b16937\nDiagnose does not write PosterBoard. Access acquisition temporarily swaps this app's own group Caches, consumes an exact-path token, then restores Caches immediately.\n"
    @Published var container = ""
    @Published var archive: URL?
    @Published var busy = false
    @Published var importError: String?
    @Published var rule: IdentityRule = .strict

    func append(_ text: String) { log += text + (text.hasSuffix("\n") ? "" : "\n") }
    func run(apply: Bool) {
        guard !busy else { return }
        busy = true
        let entered = container, selected = archive, selectedRule = rule
        append("\n\(apply ? "APPLY" : "DIAGNOSE") · \(Date()) · rule=\(selectedRule.rawValue)\niOS \(UIDevice.current.systemVersion) · bundle \(Bundle.main.bundleIdentifier ?? "?")")
        let logger: (String) -> Void = { [weak self] line in
            DispatchQueue.main.async { self?.append(line) }
        }
        Task {
            do {
                let path = try await Task.detached(priority: .userInitiated) {
                    let path = entered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? try ProbeDiagnostics.discover(log: logger)
                        : try PosterBoardStore.canonicalContainer(entered)
                    let lease = try PosterBoardLease(path: path, log: logger)
                    do {
                        ProbeDiagnostics.inspect(lease, log: logger)
                        if apply {
                            guard let selected else { throw PosterBoardStore.failure("Import a .tendies first.") }
                            try PosterBoardStore.validateIdentity(lease.effectiveURL, lease: lease, rule: selectedRule)
                            let fm = FileManager.default
                            let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                            try fm.createDirectory(at: temp, withIntermediateDirectories: true)
                            defer { try? fm.removeItem(at: temp) }
                            let unpack = temp.appendingPathComponent("unpack")
                            let prepared = temp.appendingPathComponent("prepared")
                            try fm.createDirectory(at: unpack, withIntermediateDirectories: true)
                            try fm.createDirectory(at: prepared, withIntermediateDirectories: true)
                            let parser = TendiesArchive()
                            try parser.extractValidatedArchive(selected, to: unpack)
                            let found = parser.findDescriptorsWithExtensions(in: unpack, defaultExt: ProbeDiagnostics.provider)
                            guard !found.isEmpty else { throw PosterBoardStore.failure("No descriptors found.") }
                            var descriptors: [(url: URL, ext: String)] = []
                            for item in found {
                                guard item.ext == ProbeDiagnostics.provider || item.ext == "com.apple.Posters.CollectionsPosterApp" else {
                                    throw PosterBoardStore.failure("Unsupported provider \(item.ext). Nothing applied.")
                                }
                                let fresh = try parser.prepareDescriptor(item.url, in: prepared)
                                logger("Fresh descriptor UUID = \(fresh.lastPathComponent)")
                                descriptors.append((url: fresh, ext: ProbeDiagnostics.provider))
                            }
                            let backup = fm.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("TendiesBackups")
                            let count = try PosterBoardStore.install(descriptors, container: lease.effectiveURL,
                                resetProtections: true, backupRoot: backup, lease: lease, rule: selectedRule, log: logger)
                            logger("COPY VERIFIED · \(count) descriptor(s). Gallery appearance is NOT yet verified. No respring performed.")
                        } else {
                            logger("DIAGNOSE COMPLETE · no PosterBoard writes.")
                        }
                        try lease.close()
                        return path
                    } catch {
                        do { try lease.close() } catch { logger("CLEANUP ERROR \(ProbeDiagnostics.describe(error))") }
                        throw error
                    }
                }.value
                container = path
            } catch { append("ERROR · \(ProbeDiagnostics.describe(error))") }
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
            Picker("Identity rule", selection: $model.rule) {
                ForEach(IdentityRule.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).disabled(model.busy)
            HStack(spacing: 8) {
                Button("Import .tendies") {
                    model.append("PICKER requested")
                    picker = true
                }
                Button("Diagnose") { model.run(apply: false) }
                Button("Apply") { confirm = true }.disabled(model.archive == nil)
            }.buttonStyle(.bordered).tint(acid).font(.caption.bold()).disabled(model.busy)
            if model.archive != nil { Text("ARCHIVE READY · new UUID on every Apply").font(.caption2.monospaced()).foregroundStyle(acid) }
            HStack {
                Text("SESSION LOG").font(.caption2.monospaced().bold()).foregroundStyle(.gray)
                Spacer()
                Button("Copy Log") { UIPasteboard.general.string = model.log }.font(.caption.bold()).tint(acid)
            }
            ScrollView([.vertical, .horizontal]) {
                Text(model.log).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
            }.background(.black).overlay(Rectangle().stroke(.white.opacity(0.15)))
            Text("Experimental. Apply adds wallpaper descriptors and updates PosterBoard preferences. Backups are kept in Files.")
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
        .alert("Apply experimental wallpaper?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Apply", role: .destructive) { model.run(apply: true) }
        } message: {
            Text("This writes new CollectionsPoster descriptors and PosterBoard preferences using the selected identity rule. Existing descriptors stay untouched. The wallpaper picker may still need a device restart.")
        }
    }
}
