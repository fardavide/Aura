import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

extension View {
    /// Hands a finished file to the platform's own destination UI — the iOS share sheet, the macOS
    /// save panel — and calls `onFinish` once it closes, whatever the user chose.
    ///
    /// Dismissing without picking anywhere is **not** a failure: the caller discards its temporary
    /// copy and says nothing, which is why there is one callback rather than a success/cancel pair.
    /// The app never picks a destination itself and never keeps the file.
    public func fileDestination(
        _ file: Binding<FileDestinationRequest?>,
        onFinish: @escaping () -> Void
    ) -> some View {
        modifier(FileDestinationModifier(file: file, onFinish: onFinish))
    }
}

/// A file waiting to be saved somewhere. `Identifiable` so it can drive a sheet directly.
public struct FileDestinationRequest: Identifiable, Equatable, Sendable {
    public let fileUrl: URL
    /// Pre-fills the save panel and names the share-sheet item.
    public let fileName: String

    public init(fileUrl: URL, fileName: String) {
        self.fileUrl = fileUrl
        self.fileName = fileName
    }

    public var id: URL { fileUrl }
}

#if os(iOS)
private struct FileDestinationModifier: ViewModifier {
    @Binding var file: FileDestinationRequest?
    let onFinish: () -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $file, onDismiss: onFinish) { request in
            ShareSheet(request: request)
                // The share sheet is the system's; Aura draws nothing over it and disables nothing
                // behind it.
                .ignoresSafeArea()
        }
    }
}

/// `UIActivityViewController` — AirDrop, Messages, Mail, Save Video, Save to Files. `ShareLink`
/// cannot serve here: it needs its item when the view is built, and this file only exists once the
/// transfer lands.
private struct ShareSheet: UIViewControllerRepresentable {
    let request: FileDestinationRequest

    func makeUIViewController(context: Context) -> UIActivityViewController {
        // A named copy in a fresh directory: the activity controller shows the file's own name, and
        // the transfer's temporary file is a UUID with no extension.
        let named = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
            .appending(path: request.fileName, directoryHint: .notDirectory)
        try? FileManager.default.createDirectory(
            at: named.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? FileManager.default.copyItem(at: request.fileUrl, to: named)
        return UIActivityViewController(activityItems: [named], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#else
private struct FileDestinationModifier: ViewModifier {
    @Binding var file: FileDestinationRequest?
    let onFinish: () -> Void

    func body(content: Content) -> some View {
        content.onChange(of: file) { _, request in
            guard let request else { return }
            present(request)
        }
    }

    private func present(_ request: FileDestinationRequest) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = request.fileName
        panel.canCreateDirectories = true
        panel.begin { response in
            if response == .OK, let destination = panel.url {
                try? FileManager.default.removeItem(at: destination)
                try? FileManager.default.copyItem(at: request.fileUrl, to: destination)
            }
            file = nil
            onFinish()
        }
    }
}
#endif
