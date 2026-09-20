import Foundation

import ExportsDomain

/// Replays a canned transfer: emits `steps` through the progress callback in order, then answers
/// with `result`. Records what it was asked to download and what was discarded, so a test can hold
/// the temporary-file contract ("cleaned after hand-off, cancel and failure alike").
public final class FakeExportDownloader: ExportDownloading, @unchecked Sendable {
    public var result: Result<DownloadedExport, ExportsError>
    public var steps: [ExportTransfer]
    /// Never finishes after reporting `steps` — parks the transfer on its last progress value so a
    /// snapshot can capture the mid-flight card without racing a completion.
    public var staysInFlight: Bool
    public private(set) var downloaded: [ExportId] = []
    public private(set) var discarded: [DownloadedExport] = []

    public init(
        _ result: Result<DownloadedExport, ExportsError> = .success(
            DownloadedExport(fileUrl: URL(filePath: "/tmp/clip.mp4"), fileName: "clip.mp4")
        ),
        steps: [ExportTransfer] = [],
        staysInFlight: Bool = false
    ) {
        self.result = result
        self.steps = steps
        self.staysInFlight = staysInFlight
    }

    public func download(
        _ export: Export,
        onProgress: @escaping @Sendable (ExportTransfer) -> Void
    ) async throws(ExportsError) -> DownloadedExport {
        downloaded.append(export.id)
        for step in steps {
            onProgress(step)
        }
        if staysInFlight {
            // Cancellable, so the centre's own cancel path still works against this fake.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
            }
        }
        return try result.get()
    }

    public func discard(_ download: DownloadedExport) {
        discarded.append(download)
    }
}
