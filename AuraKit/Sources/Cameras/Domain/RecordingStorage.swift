/// The recording-disk status for the grid's summary card: free/total bytes of the recordings
/// volume and the effective retention in days (nil when nothing is kept). Assembled from
/// `/api/stats` (disk) and the server's `record` config (retention).
public struct RecordingStorage: Equatable, Sendable {
    public let freeBytes: Int64
    public let totalBytes: Int64
    public let retentionDays: Int?

    public init(freeBytes: Int64, totalBytes: Int64, retentionDays: Int?) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
        self.retentionDays = retentionDays
    }
}
