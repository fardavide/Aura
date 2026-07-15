import Foundation
import Observation

import CamerasDomain
import CamerasEntities

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
    /// The activity Frigate is currently tracking, keyed by camera — empty when there is none or
    /// the (best-effort) fetch failed, so the grid still loads without badges.
    public private(set) var activity: [CameraName: CameraActivity] = [:]

    private let observeCameras: ObserveCameras
    private let getCameraActivity: GetCameraActivity
    private let imageLoader: any CameraImageLoading
    private var observation: Task<Void, Never>?
    private var previews: [CameraName: Data] = [:]
    private var offlineCameras: Set<CameraName> = []

    public init(
        observeCameras: ObserveCameras,
        getCameraActivity: GetCameraActivity,
        imageLoader: any CameraImageLoading
    ) {
        self.observeCameras = observeCameras
        self.getCameraActivity = getCameraActivity
        self.imageLoader = imageLoader
    }

    isolated deinit {
        observation?.cancel()
    }

    /// Live cameras — the loaded ones whose preview still resolved (not seen offline).
    public var liveCount: Int {
        guard case .loaded(let cameras) = state else { return 0 }
        return cameras.filter { !offlineCameras.contains($0.name) }.count
    }

    /// Loaded cameras whose preview still failed to load — our one honest per-camera offline signal
    /// until `/api/stats` is wired.
    public var offlineCount: Int {
        guard case .loaded(let cameras) = state else { return 0 }
        return cameras.filter { offlineCameras.contains($0.name) }.count
    }

    /// Fetches and replaces the content. Only the very first load shows the full-screen spinner: a
    /// re-appearance re-fetches behind the current content, and a failed refresh keeps the last good
    /// content. The view model owns preview and activity loading so the tiles stay pure — they never
    /// write back into it mid-render.
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
            return
        }
        guard case .loaded(let cameras) = state else { return }
        await refreshContent(for: cameras)
    }

    /// Re-pulls the stills and activity for the cameras already on screen — the grid drives this on
    /// a timer so the "LIVE" tiles and badges stay current without a manual pull-to-refresh. Cheaper
    /// than `load()`: it doesn't re-subscribe to the camera list.
    public func refresh() async {
        guard case .loaded(let cameras) = state else { return }
        await refreshContent(for: cameras)
    }

    public func activity(for camera: Camera) -> CameraActivity? {
        activity[camera.name]
    }

    public func previewImage(for camera: Camera) -> Data? {
        previews[camera.name]
    }

    /// Whether the grid saw this camera's preview still fail to load.
    public func isOffline(_ camera: Camera) -> Bool {
        offlineCameras.contains(camera.name)
    }

    private func refreshContent(for cameras: [Camera]) async {
        // Best-effort: a missing badge must never fail the grid.
        activity = (try? await getCameraActivity.execute()) ?? [:]
        await loadPreviews(for: cameras)
    }

    private func loadPreviews(for cameras: [Camera]) async {
        await withTaskGroup(of: (CameraName, Data?).self) { group in
            for camera in cameras {
                group.addTask { [imageLoader] in
                    (camera.name, await imageLoader.previewImage(for: camera.name))
                }
            }
            for await (name, data) in group {
                if let data {
                    previews[name] = data
                    offlineCameras.remove(name)
                } else {
                    offlineCameras.insert(name)
                }
            }
        }
    }
}
