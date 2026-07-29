import Foundation
import SwiftUI

import CamerasEntities

/// Renders one small still from a past-hour preview clip's playable source, `offset` seconds in;
/// nil on failure. Internal seam: the real implementation runs `AVAssetImageGenerator` over the
/// authed asset, which a test can't.
@MainActor
protocol FilmstripThumbnailGenerating {
    func thumbnail(from source: CameraStreamSource, at offset: TimeInterval) async -> Image?
}
