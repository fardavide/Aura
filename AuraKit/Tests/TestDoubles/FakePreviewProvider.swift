import Foundation

import CamerasEntities
import TimelineDomain

public struct FakePreviewProvider: CameraPreviewProviding {
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

    public func clips(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewClip] {
        clips
    }

    public func frames(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewFrame] {
        frames
    }

    public func clipSource(_ clip: PreviewClip) -> CameraStreamSource {
        source
    }
}
