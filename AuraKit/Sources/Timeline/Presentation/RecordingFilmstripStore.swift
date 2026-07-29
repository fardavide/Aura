import Foundation
import Observation
import SwiftUI

import CamerasEntities
import CommonPlayer
import TimelineDomain

/// Loads and caches the Hour-zoom filmstrip's thumbnails, one per `FilmstripSlots` instant.
///
/// A completed hour's slot is a still generated from that hour's low-res `preview.mp4`; a live-hour
/// slot (no mp4 assembled yet) is the nearest still preview frame at or before it. Each thumbnail
/// is cached against the material it was rendered from, so a slot regenerates only when its
/// material changes — the live hour completing into a clip — and never while the viewport merely
/// slides around it.
@Observable
@MainActor
public final class RecordingFilmstripStore {
    /// The loaded thumbnails by slot instant. A missing entry renders as a placeholder slot.
    public private(set) var images: [Date: Image] = [:]

    private let camera: CameraName
    private let previews: GetCameraPreviews
    private let imageLoader: any PreviewImageLoading
    private let generator: any FilmstripThumbnailGenerating
    private let cacheLimit: Int
    private var clips: [PreviewClip] = []
    private var frames: [PreviewFrame] = []
    /// The span the material was last fetched for. Scrubbing slides the slots inside a frozen
    /// span, so material re-reads happen only when the live edge extends it.
    private var materialSpan: TimeRange?
    /// What each cached thumbnail was rendered from — a slot regenerates only when this changes.
    private var resolved: [Date: FilmstripMaterial] = [:]

    public convenience init(
        camera: CameraName,
        previews: GetCameraPreviews,
        imageLoader: any PreviewImageLoading
    ) {
        self.init(
            camera: camera,
            previews: previews,
            imageLoader: imageLoader,
            generator: AssetFilmstripThumbnailGenerator(),
            // A day of slots — well past what one screen visit scrubs, ~20 MB of stills at most.
            cacheLimit: 144
        )
    }

    init(
        camera: CameraName,
        previews: GetCameraPreviews,
        imageLoader: any PreviewImageLoading,
        generator: any FilmstripThumbnailGenerating,
        cacheLimit: Int
    ) {
        self.camera = camera
        self.previews = previews
        self.imageLoader = imageLoader
        self.generator = generator
        self.cacheLimit = cacheLimit
    }

    /// Brings the given slots' thumbnails up to date against the span's material.
    public func update(slots: [Date], span: TimeRange) async {
        await fetchMaterialIfNeeded(for: span)
        for slot in slots {
            await resolve(slot)
        }
        evict(keeping: slots)
    }

    private func fetchMaterialIfNeeded(for span: TimeRange) async {
        guard span != materialSpan else { return }
        // A failed clip read keeps the last good material and leaves the span unmarked, so the
        // next update retries; frames are best-effort on top (the tile's rule, mirrored).
        guard let fetchedClips = try? await previews.clips(for: camera, in: span) else { return }
        clips = fetchedClips
        frames = (try? await previews.frames(for: camera, in: span)) ?? frames
        materialSpan = span
    }

    private func resolve(_ slot: Date) async {
        guard let material = material(at: slot), material != resolved[slot] else { return }
        // A failed render stays unresolved rather than caching the failure — a later update retries.
        guard let image = await render(material, at: slot) else { return }
        images[slot] = image
        resolved[slot] = material
    }

    /// What the slot should be rendered from: the clip holding it, or — with no clip assembled for
    /// its hour yet — the nearest live-hour still at or before it. The `atOrBefore` filter is what
    /// keeps a historical slot inside a footage gap from borrowing a *current*-hour still: every
    /// frame the server lists is newer than such a slot, so none qualifies.
    private func material(at slot: Date) -> FilmstripMaterial? {
        if let clip = clips.first(where: { $0.contains(slot) }) { return .clip(clip) }
        if let frame = frames.mostRecent(atOrBefore: slot) { return .frame(frame) }
        return nil
    }

    /// Keeps the cache bounded: a week scrubbed at Hour zoom is ~1000 slots of bitmaps, far more
    /// than a screen visit needs. Drops the thumbnails farthest from the batch just requested —
    /// the ones a returning viewport is least likely to ask for next.
    private func evict(keeping slots: [Date]) {
        guard images.count > cacheLimit, let newest = slots.max(), let oldest = slots.min() else { return }
        let byDistance = images.keys.sorted { distance($0, from: oldest, to: newest) > distance($1, from: oldest, to: newest) }
        for slot in byDistance.prefix(images.count - cacheLimit) {
            images[slot] = nil
            resolved[slot] = nil
        }
    }

    private func distance(_ slot: Date, from oldest: Date, to newest: Date) -> TimeInterval {
        max(oldest.timeIntervalSince(slot), slot.timeIntervalSince(newest), 0)
    }

    private func render(_ material: FilmstripMaterial, at slot: Date) async -> Image? {
        switch material {
        case .clip(let clip):
            let offset = slot.timeIntervalSince(clip.range.start)
            return await generator.thumbnail(from: previews.clipSource(clip), at: offset)
        case .frame(let frame):
            return await imageLoader.frameImage(frame).flatMap(platformImage(from:))
        }
    }
}

/// The source a slot's thumbnail was rendered from.
private enum FilmstripMaterial: Equatable {
    case clip(PreviewClip)
    case frame(PreviewFrame)
}
