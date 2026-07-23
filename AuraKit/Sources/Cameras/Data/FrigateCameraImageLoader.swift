import Foundation

import CamerasDomain
import CamerasEntities
import CommonFrigate
import CommonNetwork

/// Fetches a camera's `latest.jpg` still through the authenticated HTTP client. "Frigate" is
/// the implementation detail behind the `CameraImageLoading` domain protocol.
public struct FrigateCameraImageLoader: CameraImageLoading {
    private let config: ServerConfig
    private let api: FrigateApiClient
    private let height: Int

    public init(config: ServerConfig, httpClient: any HttpClient, height: Int = 600) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
        self.height = height
    }

    public func previewImage(for camera: CameraName) async -> Data? {
        try? await api.get(
            FrigateMediaUrl.latestImage(base: config.baseUrl, camera: camera.value, height: height)
        )
    }
}
