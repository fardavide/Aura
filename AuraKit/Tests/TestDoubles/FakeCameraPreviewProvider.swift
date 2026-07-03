import Foundation

import CamerasDomain
import TimelineDomain

/// Serves fixed preview material for every camera; the defaults (no clips, no frames) drive
/// tiles to their placeholder state.
public final class FakeCameraPreviewProvider: CameraPreviewProviding, @unchecked Sendable {
    public var clips: [PreviewClip]
    public var frames: [PreviewFrame]
    public var source: CameraStreamSource

    public init(
        clips: [PreviewClip] = [],
        frames: [PreviewFrame] = [],
        source: CameraStreamSource = CameraStreamSource(url: URL(filePath: "/unused"), headers: [:])
    ) {
        self.clips = clips
        self.frames = frames
        self.source = source
    }

    public func clips(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewClip] { clips }
    public func frames(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewFrame] { frames }
    public func clipSource(_ clip: PreviewClip) -> CameraStreamSource { source }
}
