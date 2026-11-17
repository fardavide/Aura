import AVFoundation
import Foundation
import SwiftUI

import CamerasEntities
import CommonPlayer

/// Renders filmstrip stills with `AVAssetImageGenerator` over the authed preview clip.
///
/// The filmstrip can use a nearby keyframe for a ten-minute slot. The camera picker requests a
/// tighter tolerance because every tile represents the same instant.
struct AssetFilmstripThumbnailGenerator: FilmstripThumbnailGenerating {
    let timeTolerance: TimeInterval

    func thumbnail(from source: CameraStreamSource, at offset: TimeInterval) async -> Image? {
        let generator = AVAssetImageGenerator(asset: makeAuthedAsset(url: source.url, headers: source.headers))
        generator.appliesPreferredTrackTransform = true
        // A strip cell shows ~80×72 points; Frigate's preview frames are ~320×180 already, so this
        // is a guard against a server configured with larger previews, not a routine downscale.
        generator.maximumSize = CGSize(width: 384, height: 384)
        generator.requestedTimeToleranceBefore = CMTime(seconds: timeTolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = generator.requestedTimeToleranceBefore
        let time = CMTime(seconds: offset, preferredTimescale: 600)
        guard let cgImage = try? await generator.image(at: time).image else { return nil }
        return Image(decorative: cgImage, scale: 1)
    }
}
