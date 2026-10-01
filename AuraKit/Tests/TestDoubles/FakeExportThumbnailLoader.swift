import Foundation

import ExportsDomain

/// Answers with canned image bytes, or nil to stand in for an export the server kept no still for.
public final class FakeExportThumbnailLoader: ExportThumbnailLoading, Sendable {
    public let data: Data?

    public init(data: Data? = nil) {
        self.data = data
    }

    public func thumbnail(for export: Export) async -> Data? {
        return data
    }
}
