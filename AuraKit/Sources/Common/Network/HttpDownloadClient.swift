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

    /// Progress is **polled off the task's own `Progress`** rather than read from a
    /// `URLSessionDownloadDelegate`.
    ///
    /// A delegate has to be an `NSObject`, and an `NSObject` subclass in `CommonNetwork` is
    /// registered with the ObjC runtime twice at test time: once from the app's `AuraKit` package
    /// framework and once from `AuraTests`, which links `CommonNetwork` statically through
    /// `TestDoubles`. The runtime warns that this "may cause spurious casting failures and
    /// mysterious crashes", and it did — the app-hosted snapshot suite crashed on CI, taking a
    /// different, unrelated handful of tests down on each run. `CommonPlayer`'s own `NSObject`
    /// coordinator escapes this only because nothing in the test bundle links that target.
    ///
    /// Polling costs one read per tick and the design throttles the bar to 10 Hz anyway, so the
    /// delegate bought nothing the poll does not.
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

        let running = RunningDownload()
        let poller = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.progressInterval)
                guard !Task.isCancelled, let progress = running.progress else { continue }
                // A total of 0 or −1 is how a chunked response reports an unknown length; passing
                // it on as a number would draw a bar running backwards.
                onProgress(
                    progress.completedUnitCount,
                    progress.totalUnitCount > 0 ? progress.totalUnitCount : nil
                )
            }
        }
        defer { poller.cancel() }

        let (temporaryUrl, response) = try await withTaskCancellationHandler {
            // The continuation is annotated explicitly: inferring a tuple payload through it
            // defeats the type checker outright ("failed to produce diagnostic for expression").
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(URL, URLResponse), any Error>) in
                let task = session.downloadTask(with: request) { location, response, error in
                    guard let location, let response else {
                        continuation.resume(throwing: error ?? URLError(.badServerResponse))
                        return
                    }
                    // `location` is deleted the moment this handler returns, so the body is moved
                    // out of it here rather than after the await.
                    let fileUrl = FileManager.default.temporaryDirectory
                        .appending(path: UUID().uuidString, directoryHint: .notDirectory)
                    do {
                        try FileManager.default.moveItem(at: location, to: fileUrl)
                        continuation.resume(returning: (fileUrl, response))
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                running.task = task
                task.resume()
            }
        } onCancel: {
            running.task?.cancel()
        }

        guard let http = response as? HTTPURLResponse else {
            try? FileManager.default.removeItem(at: temporaryUrl)
            throw URLError(.badServerResponse)
        }
        // A final exact reading, so the bar always lands on full rather than wherever the last
        // tick happened to catch it.
        onProgress(http.expectedContentLength, http.expectedContentLength > 0 ? http.expectedContentLength : nil)
        return (temporaryUrl, http)
    }

    private static let idleTimeout: TimeInterval = 30
    private static let progressInterval: Duration = .milliseconds(100)
}

/// Holds the in-flight task so the cancellation handler and the progress poll can reach it. A
/// plain Swift class on purpose — see `download`'s doc comment for why nothing here may be an
/// `NSObject`.
private final class RunningDownload: @unchecked Sendable {
    var task: URLSessionDownloadTask?

    var progress: Progress? { task?.progress }
}
