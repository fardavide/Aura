import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork

/// Builds the go2rtc HLS live stream (proxied through Frigate) for a camera, carrying Basic
/// auth when credentials are configured. Uses the camera's first stream name.
public struct FrigateCameraStreamProvider: CameraStreamProviding {
    private let config: ServerConfig

    public init(config: ServerConfig) {
        self.config = config
    }

    public func streamSource(for camera: Camera) -> CameraStreamSource? {
        guard let src = camera.streamNames.first else { return nil }
        let url = FrigateLiveUrl.stream(base: config.baseUrl, src: src)
        var headers: [String: String] = [:]
        if let auth = AuthorizationHeader.basic(username: config.username, password: config.password) {
            headers["Authorization"] = auth
        }
        return CameraStreamSource(url: url, headers: headers)
    }
}
