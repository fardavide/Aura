import Foundation
import Observation

import CamerasDomain

@Observable
@MainActor
public final class CameraGridViewModel {
    public enum State: Equatable {
        case loading
        case loaded([Camera])
        case empty
        case failed(CamerasError)
    }

    public private(set) var state: State = .loading

    private let getCameras: GetCameras
    private let imageLoader: any CameraImageLoading

    public init(getCameras: GetCameras, imageLoader: any CameraImageLoading) {
        self.getCameras = getCameras
        self.imageLoader = imageLoader
    }

    /// Fetches and replaces the content. Only the very first load shows the full-screen spinner
    /// (the initial state): a re-appearance re-fetches behind the current content, and a failed
    /// refresh keeps the last good content instead of swapping it for a full-screen error.
    public func load() async {
        do {
            let cameras = try await getCameras.execute()
            state = cameras.isEmpty ? .empty : .loaded(cameras)
        } catch {
            if case .loaded = state { return }
            state = .failed(error)
        }
    }

    public func previewImage(for camera: Camera) async -> Data? {
        await imageLoader.previewImage(for: camera.name)
    }
}
