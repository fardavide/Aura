import Foundation

import CommonFrigate
import CommonNetwork
import ExportsDomain

/// Fetches an export's still through the authenticated HTTP client.
public struct FrigateExportThumbnailLoader: ExportThumbnailLoading {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func thumbnail(for export: Export) async -> Data? {
        guard
            let path = export.thumbnailPath,
            let url = FrigateExportMediaUrl.media(base: config.baseUrl, serverPath: path)
        else {
            return nil
        }
        return try? await api.get(url)
    }
}
