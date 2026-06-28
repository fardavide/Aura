import Foundation

/// Loads one current-hour preview frame's bytes (authenticated); nil on failure → placeholder.
public protocol PreviewImageLoading: Sendable {
    func frameImage(_ frame: PreviewFrame) async -> Data?
}
