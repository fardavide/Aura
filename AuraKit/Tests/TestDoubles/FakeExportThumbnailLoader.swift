import Foundation

import ExportsDomain

/// Answers with canned image bytes, or nil to stand in for an export the server kept no still for.
public final class FakeExportThumbnailLoader: ExportThumbnailLoading, @unchecked Sendable {
    public var data: Data?
    public private(set) var requested: [ExportId] = []

    public init(data: Data? = nil) {
        self.data = data
    }

    public func thumbnail(for export: Export) async -> Data? {
        requested.append(export.id)
        return data
    }
}
