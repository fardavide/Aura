import Foundation

/// Loads a camera's preview still (the grid tile image). Implemented in the Data layer with
/// an authenticated request; returns nil on any failure so the UI shows a placeholder.
public protocol CameraImageLoading: Sendable {
    func previewImage(for camera: CameraName) async -> Data?
}
