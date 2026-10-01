import Foundation

import CamerasDomain
import CamerasEntities
import CommonFrigate
import CommonNetwork

/// Uses the selected route's go2rtc endpoint when configured; otherwise the legacy Frigate
/// proxy. Frigate credentials belong only to the proxy. Uses the camera's first stream name.
public struct FrigateCameraStreamProvider: CameraStreamProviding {
    private let config: ServerConfig
    private let go2rtcBaseUrl: URL?

    public init(config: ServerConfig, go2rtcBaseUrl: URL?) {
        self.config = config
        self.go2rtcBaseUrl = go2rtcBaseUrl
    }

    public func streamSource(for camera: Camera) -> CameraStreamSource? {
        guard let src = camera.streamNames.first else { return nil }
        if let go2rtcBaseUrl {
            return CameraStreamSource(url: Go2rtcLiveUrl.stream(base: go2rtcBaseUrl, src: src), headers: [:])
        }
        let url = FrigateLiveUrl.stream(base: config.baseUrl, src: src)
        var headers: [String: String] = [:]
        if let auth = AuthorizationHeader.basic(username: config.username, password: config.password) {
            headers["Authorization"] = auth
        }
        return CameraStreamSource(url: url, headers: headers)
    }
}
