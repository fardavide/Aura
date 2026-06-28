import AVKit
import Foundation
import Observation

import CamerasDomain
import CommonPlayer
import TimelineDomain

/// One camera tile in the synced grid. Loads the day's preview clips once, then seeks the active
/// clip's player to the shared scrub instant — coalesced through a `PreviewTileController`.
@Observable
@MainActor
public final class PreviewTileViewModel {
    public enum Display {
        case loading
        case clip(AVPlayer)
        case unavailable
        case failed
    }

    public let camera: Camera
    public private(set) var display: Display = .loading

    private let previews: GetCameraPreviews
    private var clips: [PreviewClip] = []
    private var activeClip: PreviewClip?
    @ObservationIgnored private lazy var controller = PreviewTileController(scrubber: self, tolerance: 0.5)

    public init(camera: Camera, previews: GetCameraPreviews) {
        self.camera = camera
        self.previews = previews
    }

    /// Loads the visible range's preview clips, then shows the frame at the current scrub instant.
    public func prepare(range: TimeRange, at instant: Date) async {
        do {
            clips = try await previews.clips(for: camera.name, in: range)
            activeClip = nil
        } catch {
            display = .failed
            return
        }
        controller.scrub(to: instant)
    }

    public func scrub(to time: Date) {
        controller.scrub(to: time)
    }
}

extension PreviewTileViewModel: PreviewScrubber {
    func scrub(to time: Date, completion: @escaping @MainActor () -> Void) {
        guard let clip = clip(for: time) else {
            activeClip = nil
            display = .unavailable
            completion()
            return
        }
        if clip != activeClip {
            activeClip = clip
            let source = previews.clipSource(clip)
            display = .clip(makeAuthedPlayer(url: source.url, headers: source.headers))
        }
        guard case let .clip(player) = display else {
            completion()
            return
        }
        // Clamp into the clip so the live edge (no finished clip yet) shows the latest footage.
        let target = Swift.min(Swift.max(time, clip.range.start), clip.range.end)
        player.seek(
            to: CMTime(seconds: target.timeIntervalSince(clip.range.start), preferredTimescale: 600),
            toleranceBefore: CMTime(seconds: 0.5, preferredTimescale: 600),
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
        ) { _ in
            Task { @MainActor in completion() }
        }
    }

    /// The clip covering `time`; or, at/after the live edge, the most recent clip so tiles show
    /// the latest recorded footage instead of an empty placeholder.
    private func clip(for time: Date) -> PreviewClip? {
        if let covering = clips.first(where: { $0.contains(time) }) {
            return covering
        }
        if let latest = clips.max(by: { $0.range.start < $1.range.start }), time >= latest.range.end {
            return latest
        }
        return nil
    }
}
