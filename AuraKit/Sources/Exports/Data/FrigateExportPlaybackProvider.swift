import Foundation

import CamerasEntities
import CommonFrigate
import CommonNetwork
import ExportsDomain

/// Resolves an export to its authenticated media URL plus the headers the player must send.
///
/// An export is a finished progressive mp4 served from the media root, not an HLS playlist, so the
/// header-carrying `AVURLAsset` path works here — the segment sub-request problem that pushes live
/// and VOD playback onto a query-string token does not arise.
public struct FrigateExportPlaybackProvider: ExportPlaybackProviding {
    private let config: ServerConfig

    public init(config: ServerConfig) {
        self.config = config
    }

    public func playbackSource(for export: Export) -> CameraStreamSource {
        CameraStreamSource(url: mediaUrl(for: export), headers: authHeaders)
    }

    /// The path was validated when the export was mapped, so a refusal here is unreachable — the
    /// base URL is the fallback rather than a crash, since a player showing nothing is a better
    /// outcome than an app that stops.
    private func mediaUrl(for export: Export) -> URL {
        FrigateExportMediaUrl.media(base: config.baseUrl, serverPath: export.videoPath) ?? config.baseUrl
    }

    private var authHeaders: [String: String] {
        guard let auth = AuthorizationHeader.basic(username: config.username, password: config.password) else {
            return [:]
        }
        return ["Authorization": auth]
    }
}
