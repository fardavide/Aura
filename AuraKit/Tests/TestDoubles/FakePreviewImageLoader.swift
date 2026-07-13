import Foundation

import TimelineDomain

/// Serves one fixed image (or `nil` — the placeholder path) for every preview frame, recording
/// which frames were asked for.
public final class FakePreviewImageLoader: PreviewImageLoading, @unchecked Sendable {
    public var image: Data?
    public private(set) var requestedFrames: [PreviewFrame] = []

    public init(image: Data? = nil) {
        self.image = image
    }

    public func frameImage(_ frame: PreviewFrame) async -> Data? {
        requestedFrames.append(frame)
        return image
    }
}
