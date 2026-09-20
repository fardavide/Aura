import Foundation

/// Loads an export's still. Implemented in the Data layer with an authenticated request; returns
/// nil on any failure, and for an export the server kept no still for at all — both end at the same
/// placeholder, which is why that placeholder must not look like an error.
public protocol ExportThumbnailLoading: Sendable {
    func thumbnail(for export: Export) async -> Data?
}
