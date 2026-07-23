import Foundation

import CamerasEntities
import CommonFrigate
import CommonNetwork
import TimelineDomain

/// Fetches a camera's preview material and resolves a clip's playable (authed) source.
public struct FrigatePreviewSourceProvider: CameraPreviewProviding {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func clips(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewClip] {
        let url = FrigatePreviewUrl.clipList(
            base: config.baseUrl, camera: camera.value,
            after: range.start.timeIntervalSince1970, before: range.end.timeIntervalSince1970
        )
        let data = try await get(url)
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
        let data = try await get(url)
        do {
            return try JSONDecoder().decode([String].self, from: data).toFrames(camera: camera)
        } catch {
            throw TimelineError.invalidData
        }
    }

    public func clipSource(_ clip: PreviewClip) -> CameraStreamSource {
        var headers: [String: String] = [:]
        if let auth = AuthorizationHeader.basic(username: config.username, password: config.password) {
            headers["Authorization"] = auth
        }
        return CameraStreamSource(
            url: FrigatePreviewUrl.clipMedia(base: config.baseUrl, path: clip.path),
            headers: headers
        )
    }

    private func get(_ url: URL) async throws(TimelineError) -> Data {
        do {
            return try await api.get(url)
        } catch {
            throw TimelineError(error)
        }
    }
}

private extension TimelineError {
    /// Translates the shared Frigate transport error into the feature's domain error at the Data
    /// boundary, so the Domain never sees Frigate vocabulary.
    init(_ error: FrigateApiError) {
        switch error {
        case .unreachable: self = .unreachable
        case .notAuthorized: self = .notAuthorized
        case .serverUnavailable: self = .serverUnavailable
        case .unknown: self = .unknown
        }
    }
}
