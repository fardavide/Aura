import Foundation
import Observation

import CamerasDomain
import SettingsDomain

@Observable
@MainActor
public final class CameraOrderViewModel {
    public enum State: Equatable {
        case loading
        case loaded([Camera])
        case failed(CamerasError)
    }

    public private(set) var state: State = .loading

    private let getCameras: GetCameras
    private let loadCameraOrder: LoadCameraOrder
    private let saveCameraOrder: SaveCameraOrder

    public init(getCameras: GetCameras, loadCameraOrder: LoadCameraOrder, saveCameraOrder: SaveCameraOrder) {
        self.getCameras = getCameras
        self.loadCameraOrder = loadCameraOrder
        self.saveCameraOrder = saveCameraOrder
    }

    public func load() async {
        // Refresh in place: only a first load or a retry from `.failed` shows the spinner — a
        // re-appearance behind an already-`.loaded` list must not blank it while it refreshes.
        if case .failed = state { state = .loading }
        do {
            let cameras = try await getCameras.execute()
            state = .loaded(cameras.sorted(byPreference: loadCameraOrder.execute()))
        } catch {
            // A failed refresh keeps the last known list — the row that pushed here already showed
            // a true count, and losing it to a transient read failure would be a worse experience
            // than a stale one.
            if case .loaded = state { return }
            state = .failed(error)
        }
    }

    public func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard case .loaded(var cameras) = state else { return }
        cameras.move(fromOffsets: source, toOffset: destination)
        state = .loaded(cameras)
        // Saved names not listed here (e.g. a camera currently disabled on the server)
        // keep their entry after the visible ones instead of being silently erased.
        let visible = cameras.map(\.name)
        let hidden = loadCameraOrder.execute().filter { !visible.contains($0) }
        saveCameraOrder.execute(visible + hidden)
    }
}
