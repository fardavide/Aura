import Foundation

import CamerasDomain
import CommonFrigate
import CommonNetwork
import CamerasEntities

/// Fetches a camera's `latest.jpg` still through the authenticated HTTP client. "Frigate" is
/// the implementation detail behind the `CameraImageLoading` domain protocol.
public struct FrigateCameraImageLoader: CameraImageLoading {
    private let config: ServerConfig
    private let httpClient: any HttpClient
    private let height: Int

    public init(config: ServerConfig, httpClient: any HttpClient, height: Int = 600) {
        self.config = config
        self.httpClient = httpClient
        self.height = height
    }

    public func previewImage(for camera: CameraName) async -> Data? {
        let url = FrigateMediaUrl.latestImage(base: config.baseUrl, camera: camera.value, height: height)
        var request = URLRequest(url: url)
        if let auth = AuthorizationHeader.basic(username: config.username, password: config.password) {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        guard
            let (data, response) = try? await httpClient.data(for: request),
            (200...299).contains(response.statusCode)
        else {
            return nil
        }
        return data
    }
}
