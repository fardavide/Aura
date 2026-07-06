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

    private let observeCameras: ObserveCameras
    private let imageLoader: any CameraImageLoading
    private var observation: Task<Void, Never>?

    public init(observeCameras: ObserveCameras, imageLoader: any CameraImageLoading) {
        self.observeCameras = observeCameras
        self.imageLoader = imageLoader
    }

    isolated deinit {
        observation?.cancel()
    }

    /// Fetches and replaces the content. Only the very first load shows the full-screen spinner
    /// (the initial state): a re-appearance re-fetches behind the current content, and a failed
    /// refresh keeps the last good content instead of swapping it for a full-screen error.
    /// Returns once the first camera list is applied; keeps observing order changes for the
    /// rest of the view model's life.
    public func load() async {
        do {
            let cameras = try await observeCameras.execute()
            // A racing load() may have assigned a fresh observation while we were suspended
            // above — cancel it too, or it would leak and keep writing state forever.
            observation?.cancel()
            await withCheckedContinuation { continuation in
                observation = Task { [weak self] in
                    var firstEmission: CheckedContinuation<Void, Never>? = continuation
                    for await list in cameras {
                        self?.state = list.isEmpty ? .empty : .loaded(list)
                        firstEmission?.resume()
                        firstEmission = nil
                    }
                    firstEmission?.resume()
                }
            }
        } catch {
            if case .loaded = state { return }
            state = .failed(error)
        }
    }

    public func previewImage(for camera: Camera) async -> Data? {
        await imageLoader.previewImage(for: camera.name)
    }
}
