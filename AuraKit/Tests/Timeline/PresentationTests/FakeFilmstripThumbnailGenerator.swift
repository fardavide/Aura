import Foundation
import SwiftUI

import CamerasEntities

@testable import TimelinePresentation

/// Stays in this test target (not `TestDoubles`): `FilmstripThumbnailGenerating` is internal to
/// `TimelinePresentation`, so a shared module cannot conform to it.
@MainActor
final class FakeFilmstripThumbnailGenerator: FilmstripThumbnailGenerating {
    var image: Image?
    private(set) var sources: [CameraStreamSource] = []
    private(set) var offsets: [TimeInterval] = []

    init(image: Image? = Image(systemName: "photo")) {
        self.image = image
    }

    func thumbnail(from source: CameraStreamSource, at offset: TimeInterval) async -> Image? {
        sources.append(source)
        offsets.append(offset)
        return image
    }
}
