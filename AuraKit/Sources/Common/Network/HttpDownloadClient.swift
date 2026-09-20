import Foundation

/// The transport seam for a *large* body: streams the response to a file on disk and reports bytes
/// as they arrive, instead of materialising the whole thing in memory the way `HttpClient` does.
///
/// Separate from `HttpClient` on purpose — a clip is tens of megabytes, and the one caller that
/// needs a progress bar is also the one caller that must not hold the file in RAM to draw it.
public protocol HttpDownloadClient: Sendable {

    /// Writes the body to a temporary file and returns its location; the caller owns that file and
    /// must delete it. `bytesExpected` is nil while the server has declared no length.
    ///
    /// Cancelling the calling task stops the transfer and removes the partial file.
    func download(
        _ request: URLRequest,
        onProgress: @escaping @Sendable (_ bytesReceived: Int64, _ bytesExpected: Int64?) -> Void
    ) async throws -> (fileUrl: URL, response: HTTPURLResponse)
}

public struct UrlSessionHttpDownloadClient: HttpDownloadClient {

    public init() {}

    public func download(
        _ request: URLRequest,
        onProgress: @escaping @Sendable (Int64, Int64?) -> Void
    ) async throws -> (fileUrl: URL, response: HTTPURLResponse) {
        let configuration = URLSessionConfiguration.default
        // An *idle* bound — reset whenever bytes arrive — so it only trips a genuine stall. No
        // `timeoutIntervalForResource` ceiling, unlike `UrlSessionHttpClient`: an export can be far
        // larger than an event clip and the user is watching a determinate bar, so a slow but
        // progressing transfer must not be killed at a fixed wall-clock cut-off. Cancellation is
        // the exit, and it is the user's.
        configuration.timeoutIntervalForRequest = Self.idleTimeout
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }

        let progress = ProgressReporter(onProgress: onProgress)
        // `download(for:delegate:)` hands back a file URL that is deleted the moment this call
        // returns, so the body is moved out of it below before anyone can read it.
        let (temporaryUrl, response) = try await session.download(for: request, delegate: progress)
        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: temporaryUrl)
            throw URLError(.badServerResponse)
        }
        let fileUrl = FileManager.default.temporaryDirectory
            .appending(path: UUID().uuidString, directoryHint: .notDirectory)
        do {
            try FileManager.default.moveItem(at: temporaryUrl, to: fileUrl)
        } catch {
            try? FileManager.default.removeItem(at: temporaryUrl)
            throw error
        }
        return (fileUrl, http)
    }

    private static let idleTimeout: TimeInterval = 30
}

/// Forwards the download task's byte counts to the caller's closure. A per-task delegate, so the
/// session itself stays delegate-free and one transfer's progress can never reach another's bar.
private final class ProgressReporter: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Int64, Int64?) -> Void

    init(onProgress: @escaping @Sendable (Int64, Int64?) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // `NSURLSessionTransferSizeUnknown` (−1) is how a chunked response reports its length;
        // passing it on as a number would draw a bar running backwards.
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil
        onProgress(totalBytesWritten, expected)
    }

    /// Required by the protocol; the async `download(for:delegate:)` overload is what actually
    /// yields the file, so there is nothing to do with it here.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}
