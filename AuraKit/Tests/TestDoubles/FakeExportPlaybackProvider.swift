import Foundation

import CamerasEntities
import ExportsDomain

/// Resolves every export to one canned source. The URL is never loaded in a snapshot — the player
/// screen is not snapshot-tested — so this exists to satisfy the screen's dependency, not to play.
public final class FakeExportPlaybackProvider: ExportPlaybackProviding, @unchecked Sendable {
    public var source: CameraStreamSource
    public private(set) var requested: [ExportId] = []

    public init(source: CameraStreamSource = CameraStreamSource(url: URL(filePath: "/dev/null"), headers: [:])) {
        self.source = source
    }

    public func playbackSource(for export: Export) -> CameraStreamSource {
        requested.append(export.id)
        return source
    }
}
