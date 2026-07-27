import Foundation

import CamerasEntities
import CommonFrigate
import CommonNetwork
import TimelineDomain

/// Reads a camera's recording segments and resolves the window's authenticated playlist. Both are
/// built from the **same** window bounds — the wall-clock mapping only holds while the footage
/// described and the stream served cover the same seconds.
public struct FrigateCameraRecordingsRepository: CameraRecordingsRepository {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func segments(for camera: CameraName, in window: TimeRange) async throws(TimelineError) -> [RecordingSegment] {
        let url = FrigateRecordingsUrl.segments(
            base: config.baseUrl, camera: camera.value,
            after: window.start.timeIntervalSince1970, before: window.end.timeIntervalSince1970
        )
        let data: Data
        do {
            data = try await api.get(url)
        } catch {
            throw TimelineError(error)
        }
        do {
            return try JSONDecoder().decode([RecordingSegmentDto].self, from: data).toSegments()
        } catch {
            throw TimelineError.invalidData
        }
    }

    public func playbackSource(for camera: CameraName, in window: TimeRange) -> CameraStreamSource {
        var headers: [String: String] = [:]
        if let auth = AuthorizationHeader.basic(username: config.username, password: config.password) {
            headers["Authorization"] = auth
        }
        return CameraStreamSource(
            url: FrigateRecordingsUrl.playlist(
                base: config.baseUrl, camera: camera.value,
                after: window.start.timeIntervalSince1970, before: window.end.timeIntervalSince1970
            ),
            headers: headers
        )
    }
}
