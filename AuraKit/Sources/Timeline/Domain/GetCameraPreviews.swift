import CamerasEntities

/// Fetches a camera's preview material (clips + frames) and resolves a clip's playable source.
public struct GetCameraPreviews: Sendable {
    private let provider: any CameraPreviewProviding

    public init(provider: any CameraPreviewProviding) {
        self.provider = provider
    }

    public func clips(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewClip] {
        try await provider.clips(for: camera, in: range)
    }

    public func frames(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewFrame] {
        try await provider.frames(for: camera, in: range)
    }

    public func clipSource(_ clip: PreviewClip) -> CameraStreamSource {
        provider.clipSource(clip)
    }
}
