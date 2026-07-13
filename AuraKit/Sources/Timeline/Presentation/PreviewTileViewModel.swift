import AVKit
import Foundation
import Observation
import SwiftUI

import CamerasDomain
import CommonPlayer
import TimelineDomain

/// One camera tile in the synced grid. Loads the day's preview material once, then shows the
/// shared scrub instant — seeking a past-hour clip's player, or, in the live hour (no `preview.mp4`
/// yet), the nearest still preview frame — coalesced through a `PreviewTileController`.
@Observable
@MainActor
public final class PreviewTileViewModel {
    public enum Display {
        case loading
        case clip(AVPlayer)
        case frame(Image)
        case unavailable
        case failed
    }

    public let camera: Camera
    public private(set) var display: Display = .loading

    private let previews: GetCameraPreviews
    private let imageLoader: any PreviewImageLoading
    private var clips: [PreviewClip] = []
    private var frames: [PreviewFrame] = []
    private var activeClip: PreviewClip?
    private var activeFrame: PreviewFrame?
    @ObservationIgnored private lazy var controller = PreviewTileController(scrubber: self, tolerance: 0.5)

    public init(camera: Camera, previews: GetCameraPreviews, imageLoader: any PreviewImageLoading) {
        self.camera = camera
        self.previews = previews
        self.imageLoader = imageLoader
    }

    /// Loads the visible range's preview material — past-hour clips and current-hour frames — then
    /// shows the frame at the current scrub instant.
    public func prepare(range: TimeRange, at instant: Date) async {
        let loadedClips: [PreviewClip]
        do {
            loadedClips = try await previews.clips(for: camera.name, in: range)
        } catch {
            display = .failed
            return
        }
        clips = loadedClips
        // Frames are best-effort: a failure degrades the live hour to the frozen-clip fallback,
        // never to a full-tile error (the clips already loaded).
        frames = (try? await previews.frames(for: camera.name, in: range)) ?? []
        activeClip = nil
        activeFrame = nil
        controller.scrub(to: instant)
    }

    public func scrub(to time: Date) {
        controller.scrub(to: time)
    }
}

extension PreviewTileViewModel: PreviewScrubber {
    func scrub(to time: Date, completion: @escaping @MainActor () -> Void) {
        // Past hours: a low-res mp4 covers this instant — seek it locally (smooth, no network).
        if let clip = clips.first(where: { $0.contains(time) }) {
            seek(clip, to: time, completion: completion)
            return
        }
        // Live hour: Frigate has no mp4 for the in-progress hour yet, so show the nearest still frame
        // — this is what keeps the tile current at the live edge instead of freezing an hour back.
        if let frame = frames.mostRecent(atOrBefore: time) {
            show(frame, completion: completion)
            return
        }
        // At/after the live edge with no frame available — fall back to the latest clip's last frame.
        if let latest = clips.max(by: { $0.range.start < $1.range.start }), time >= latest.range.end {
            seek(latest, to: time, completion: completion)
            return
        }
        activeClip = nil
        activeFrame = nil
        display = .unavailable
        completion()
    }

    private func seek(_ clip: PreviewClip, to time: Date, completion: @escaping @MainActor () -> Void) {
        activeFrame = nil
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

    private func show(_ frame: PreviewFrame, completion: @escaping @MainActor () -> Void) {
        activeClip = nil
        // Already showing this frame — skip the reload (webp is immutable, but avoid the churn).
        if frame == activeFrame, case .frame = display {
            completion()
            return
        }
        activeFrame = frame
        Task { @MainActor in
            if let image = await imageLoader.frameImage(frame).flatMap(platformImage(from:)) {
                display = .frame(image)
            }
            // On a load failure keep the current tile (don't flash) — a later scrub retries.
            completion()
        }
    }
}
