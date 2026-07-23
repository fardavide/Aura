import Foundation

import CommonFrigate
import CommonNetwork
import TimelineDomain

/// Loads a single current-hour preview frame (webp) over the authenticated HTTP client.
public struct FrigatePreviewImageLoader: PreviewImageLoading {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
    }

    public func frameImage(_ frame: PreviewFrame) async -> Data? {
        let url = FrigatePreviewUrl.frameThumbnail(base: config.baseUrl, fileName: frame.fileName)
        var request = URLRequest(url: url)
        // Bounded like the other timeline reads: a hung frame load must not leave a first-load tile
        // stuck on its spinner (the frame resolves the display) — it fails and retries next extension.
        request.timeoutInterval = timelineRequestTimeout
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
