import Foundation

import CommonFrigate
import CommonNetwork
import TimelineDomain

/// Loads a single current-hour preview frame (webp) over the authenticated HTTP client.
public struct FrigatePreviewImageLoader: PreviewImageLoading {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func frameImage(_ frame: PreviewFrame) async -> Data? {
        try? await api.get(FrigatePreviewUrl.frameThumbnail(base: config.baseUrl, fileName: frame.fileName))
    }
}
