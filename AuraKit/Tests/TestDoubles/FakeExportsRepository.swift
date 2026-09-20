import ExportsDomain

/// Replays a canned library; `result` is mutable so a test can change the outcome between calls
/// (a refresh that fails after a good first load). `singleExport`, when set, answers the by-id
/// re-read — the path a processing clip is followed on.
public final class FakeExportsRepository: ExportsRepository, @unchecked Sendable {
    public var result: Result<[Export], ExportsError>
    public var singleExport: Result<Export, ExportsError>?
    /// Holds the read open, so a test can observe what the screen does *while* a fetch is running
    /// — a fake that answers instantly leaves no in-flight window to sample.
    public var delay: Duration
    public private(set) var readCount = 0
    public private(set) var requestedIds: [ExportId] = []

    public init(
        _ result: Result<[Export], ExportsError>,
        singleExport: Result<Export, ExportsError>? = nil,
        delay: Duration = .zero
    ) {
        self.result = result
        self.singleExport = singleExport
        self.delay = delay
    }

    public func exports() async throws(ExportsError) -> [Export] {
        readCount += 1
        if delay != .zero {
            try? await Task.sleep(for: delay)
        }
        return try result.get()
    }

    public func export(id: ExportId) async throws(ExportsError) -> Export {
        requestedIds.append(id)
        guard let singleExport else { throw ExportsError.unreachable }
        return try singleExport.get()
    }
}
