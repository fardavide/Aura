import CamerasEntities

/// Resolves an export to something the player can play: the authenticated media URL and the headers
/// that must ride with it. The same shape live playback uses, so one player path serves both.
///
/// Playing does not download — the clip streams from the server and a transfer running beside it
/// owns nothing, which is why Play stays enabled on a downloading card.
public protocol ExportPlaybackProviding: Sendable {
    func playbackSource(for export: Export) -> CameraStreamSource
}
