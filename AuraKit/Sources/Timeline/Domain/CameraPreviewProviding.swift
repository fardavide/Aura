import CamerasDomain

/// Supplies per-camera preview material for the scrub grid: past-hour clips, current-hour
/// frames, and the playable source (URL + auth headers) for a clip.
public protocol CameraPreviewProviding: Sendable {
    func clips(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewClip]
    func frames(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewFrame]
    func clipSource(_ clip: PreviewClip) -> CameraStreamSource
}
