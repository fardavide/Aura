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

    public func load() async {
        state = .loading
        do {
            let cameras = try await getCameras.execute()
            state = cameras.isEmpty ? .empty : .loaded(cameras)
        } catch {
            state = .failed(error)
        }
    }

    public func previewImage(for camera: Camera) async -> Data? {
        await imageLoader.previewImage(for: camera.name)
    }
}
