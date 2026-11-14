import SwiftUI
import UniformTypeIdentifiers
import UIKit

/// Native import-as-copy picker. The filter is public.item, not a custom UTI.
/// Extension and archive validation happen only after the delegate receives a URL.
struct AnyFilePicker: UIViewControllerRepresentable {
    var selected: (URL) -> Void
    var cancelled: () -> Void
    var trace: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(owner: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        controller.delegate = context.coordinator
        controller.allowsMultipleSelection = false
        controller.shouldShowFileExtensions = true
        trace("PICKER created · UIKit public.item · asCopy=true")
        return controller
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.owner = self
    }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var owner: AnyFilePicker
        init(owner: AnyFilePicker) { self.owner = owner }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            owner.trace("PICKER delegate didPickDocumentsAt · count=\(urls.count)")
            guard let url = urls.first else {
                owner.trace("PICKER returned no URL")
                owner.cancelled()
                return
            }
            owner.selected(url)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            owner.trace("PICKER delegate cancelled · no file received")
            owner.cancelled()
        }
    }
}
