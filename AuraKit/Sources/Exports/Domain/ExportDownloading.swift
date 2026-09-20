import Foundation

/// How far a copy has got. `bytesExpected` is nil only while the server has not yet declared a
/// length; the UI draws a determinate bar the moment it can, because for a transfer the bytes are
/// genuinely known and an indeterminate sweep would be a lie.
public struct ExportTransfer: Equatable, Sendable {
    public let bytesReceived: Int64
    public let bytesExpected: Int64?

    public init(bytesReceived: Int64, bytesExpected: Int64?) {
        self.bytesReceived = bytesReceived
        self.bytesExpected = bytesExpected
    }

    /// 0…1, or nil while the length is unknown. Clamped, because a server that under-reports its
    /// own length must not drive a bar past full.
    public var fraction: Double? {
        guard let bytesExpected, bytesExpected > 0 else { return nil }
        return min(1, Double(bytesReceived) / Double(bytesExpected))
    }
}

/// A finished copy sitting in a temporary location, waiting to be handed to the platform's
/// destination UI. Aura never picks the destination and never keeps the file: whoever receives this
/// must call `discard` once the hand-off is done, cancelled or failed.
public struct DownloadedExport: Equatable, Sendable {
    public let fileUrl: URL
    /// What to pre-fill the share sheet or save panel with — Frigate's own name plus its extension.
    public let fileName: String

    public init(fileUrl: URL, fileName: String) {
        self.fileUrl = fileUrl
        self.fileName = fileName
    }
}

/// Copies an export's bytes to the device. Implemented in the Data layer over an authenticated
/// background transfer, so it survives leaving the tab and backgrounding the app.
///
/// Cancellation is ordinary task cancellation: cancelling the calling task stops the transfer and
/// discards the partial file.
public protocol ExportDownloading: Sendable {
    func download(
        _ export: Export,
        onProgress: @escaping @Sendable (ExportTransfer) -> Void
    ) async throws(ExportsError) -> DownloadedExport

    /// Deletes the temporary file. Idempotent — called after a successful hand-off, a dismissed
    /// share sheet, and a failure alike, so Aura never accumulates a hidden second library.
    func discard(_ download: DownloadedExport)
}
