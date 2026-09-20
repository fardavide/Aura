/// Copies one export to the device, reporting progress as the bytes arrive.
///
/// Refuses a clip the server is still cutting rather than letting the request fail late: a
/// processing export has no finished file behind it, and the card's Download control is disabled
/// for the same reason. The guard is here, in the Domain, so every caller inherits it.
public struct DownloadExport: Sendable {
    private let downloader: any ExportDownloading

    public init(downloader: any ExportDownloading) {
        self.downloader = downloader
    }

    public func execute(
        _ export: Export,
        onProgress: @escaping @Sendable (ExportTransfer) -> Void
    ) async throws(ExportsError) -> DownloadedExport {
        guard export.isReady else { throw ExportsError.rejected }
        return try await downloader.download(export, onProgress: onProgress)
    }

    public func discard(_ download: DownloadedExport) {
        downloader.discard(download)
    }
}
