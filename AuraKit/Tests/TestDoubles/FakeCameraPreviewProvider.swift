import Foundation

import CamerasDomain
import CamerasEntities
import TimelineDomain

/// Serves fixed preview material for every camera; the defaults (no clips, no frames) drive
/// tiles to their placeholder state. Reassign `clipsResult`/`framesResult` mid-test to change
/// what a later fetch returns (new material after a refresh, or a failure).
public final class FakeCameraPreviewProvider: CameraPreviewProviding, @unchecked Sendable {
    public var clipsResult: Result<[PreviewClip], TimelineError>
    public var framesResult: Result<[PreviewFrame], TimelineError>
    public var source: CameraStreamSource
    /// Awaited mid-fetch when set — lets a test interleave work while a clips fetch is in flight.
    public var onClips: (@Sendable () async -> Void)?
    /// How many times `clips(for:in:)` was entered — a test asserts a follow-up didn't duplicate
    /// (or cancel and restart) an in-flight first load. Incremented before `onClips` awaits, so a
    /// held-in-flight fetch already counts.
    public private(set) var clipsCallCount = 0

    public init(
        clips: [PreviewClip] = [],
        frames: [PreviewFrame] = [],
        source: CameraStreamSource = CameraStreamSource(url: URL(filePath: "/unused"), headers: [:])
    ) {
        clipsResult = .success(clips)
        framesResult = .success(frames)
        self.source = source
    }

    public func clips(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewClip] {
        clipsCallCount += 1
        if let onClips { await onClips() }
        return try clipsResult.get()
    }

    public func frames(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewFrame] {
        try framesResult.get()
    }

    public func clipSource(_ clip: PreviewClip) -> CameraStreamSource { source }
}
