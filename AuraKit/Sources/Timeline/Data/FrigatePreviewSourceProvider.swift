import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork
import TimelineDomain

/// Fetches a camera's preview material and resolves a clip's playable (authed) source.
public struct FrigatePreviewSourceProvider: CameraPreviewProviding {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
    }

    public func clips(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewClip] {
        let url = FrigatePreviewUrl.clipList(
            base: config.baseUrl, camera: camera.value,
            after: range.start.timeIntervalSince1970, before: range.end.timeIntervalSince1970
        )
        let data = try await authorizedData(url: url, config: config, httpClient: httpClient)
        do {
            return try JSONDecoder().decode([PreviewClipDto].self, from: data).toClips()
        } catch {
            throw TimelineError.invalidData
        }
    }

    public func frames(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewFrame] {
        let url = FrigatePreviewUrl.frameList(
            base: config.baseUrl, camera: camera.value,
            after: range.start.timeIntervalSince1970, before: range.end.timeIntervalSince1970
        )
        let data = try await authorizedData(url: url, config: config, httpClient: httpClient)
        do {
            return try JSONDecoder().decode([String].self, from: data).toFrames(camera: camera)
        } catch {
            throw TimelineError.invalidData
        }
    }

    public func clipSource(_ clip: PreviewClip) -> CameraStreamSource {
        CameraStreamSource(
            url: FrigatePreviewUrl.clipMedia(base: config.baseUrl, path: clip.path),
            headers: authorizationHeaders(for: config)
        )
    }
}
