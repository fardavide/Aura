import CamerasDomain

extension StatsDto {
    /// Combines the recordings-volume disk figures (`/api/stats`) with the server's retention config
    /// (`record` from `/api/config`) into the domain value. The recordings mount is Frigate's fixed
    /// path; when it's absent the disk figures are zero. "Days kept" is the largest of the four
    /// retention knobs — Frigate 0.17 has no single retain-days field — and nil when nothing is kept.
    func toRecordingStorage(record: RecordConfigDto) -> RecordingStorage {
        let mount = service?.storage?[recordingsMountPath]
        let retention = [
            record.record?.continuous?.days,
            record.record?.motion?.days,
            record.record?.alerts?.retain?.days,
            record.record?.detections?.retain?.days,
        ].compactMap { $0 }.max() ?? 0
        return RecordingStorage(
            freeBytes: bytes(fromMebibytes: mount?.free),
            totalBytes: bytes(fromMebibytes: mount?.total),
            retentionDays: retention > 0 ? Int(retention.rounded()) : nil
        )
    }
}

/// Frigate's fixed recordings volume (`frigate/const.py`: `BASE_DIR = "/media/frigate"`).
private let recordingsMountPath = "/media/frigate/recordings"
private let mebibyte = 1_048_576.0

private func bytes(fromMebibytes mib: Double?) -> Int64 {
    Int64((mib ?? 0) * mebibyte)
}
