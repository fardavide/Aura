import Foundation
import SwiftUI
import Testing

import CamerasDomain
import CamerasPresentation
import SettingsDomain
import TestDoubles

/// Screenshot tests for the camera grid screen across its states, captured on every device +
/// orientation (iOS). Tiles never show live video; a reachable camera renders the online chrome
/// over a black surface, an unreachable one the offline treatment — the reachability is settled
/// before capture so the same pixels render on every run.
@MainActor
struct CameraGridSnapshotTests {

    @Test func `given reachable cameras when loaded then it matches the reference`() async {
        // given
        let view = await cameraGridScreen(cameras: .success(snapshotCameras()), reachable: true)

        // then
        assertScreenSnapshot(view, named: "loaded")
    }

    @Test func `given tracked activity when loaded then the badges match the reference`() async {
        // given
        let view = await cameraGridScreen(
            cameras: .success(snapshotCameras()), reachable: true, activity: snapshotActivity()
        )

        // then
        assertScreenSnapshot(view, named: "activity")
    }

    @Test func `given unreachable cameras when offline then it matches the reference`() async {
        // given
        let view = await cameraGridScreen(cameras: .success(snapshotCameras()), reachable: false)

        // then
        assertScreenSnapshot(view, named: "offline")
    }

    @Test func `given no cameras when empty then it matches the reference`() async {
        // given
        let view = await cameraGridScreen(cameras: .success([]))

        // then
        assertScreenSnapshot(view, named: "empty")
    }

    @Test func `given a server failure when failed then it matches the reference`() async {
        // given
        let view = await cameraGridScreen(cameras: .failure(.serverUnavailable))

        // then
        assertScreenSnapshot(view, named: "failed")
    }
}

// MARK: - View builder

/// The camera grid screen, driven to a terminal state before rendering. The view model owns preview
/// loading, so `await load()` settles the tiles, the offline treatment, and the live/offline header
/// count before capture. `reachable` picks whether the preview loader answers with bytes (online
/// tiles) or `nil` (offline tiles).
@MainActor
private func cameraGridScreen(
    cameras: Result<[Camera], CamerasError>,
    reachable: Bool = false,
    activity: [CameraActivity] = []
) async -> some View {
    let viewModel = CameraGridViewModel(
        observeCameras: ObserveCameras(
            getCameras: GetCameras(repository: FakeCamerasRepository(cameras)),
            observeCameraOrder: ObserveCameraOrder(repository: FakeSettingsRepository())
        ),
        getCameraActivity: GetCameraActivity(repository: FakeCameraActivityRepository(.success(activity))),
        imageLoader: FakeCameraImageLoader(image: reachable ? Data([0x01]) : nil)
    )
    await viewModel.load()

    return CameraGridView(
        viewModel: viewModel,
        onOpenSettings: {},
        // Unused: the detail factory is never invoked in a grid snapshot (no navigation happens).
        makeDetailViewModel: { CameraDetailViewModel(camera: $0, streamProvider: FakeCameraStreamProvider()) }
    )
}
