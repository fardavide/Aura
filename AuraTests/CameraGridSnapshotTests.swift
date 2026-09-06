import Foundation
import SwiftUI
import Testing

import CamerasDomain
import CamerasEntities
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
        let view = await cameraGridScreen(
            cameras: .success(snapshotCameras()), reachable: true,
            today: snapshotToday(), storage: snapshotStorage()
        )

        // then
        assertScreenSnapshot(view, named: "loaded")
    }

    @Test func `given tracked activity when loaded then the badges match the reference`() async {
        // given
        let view = await cameraGridScreen(
            cameras: .success(snapshotCameras()), reachable: true, activity: snapshotActivity(),
            today: snapshotToday(), storage: snapshotStorage()
        )

        // then
        assertScreenSnapshot(view, named: "activity")
    }

    @Test func `given only a detection when loaded then the first camera is the hero`() async {
        // given — a detection must never promote a hero (only an alert may)
        let view = await cameraGridScreen(
            cameras: .success(snapshotCameras()), reachable: true, activity: snapshotDetectionOnly(),
            today: snapshotToday(), storage: snapshotStorage()
        )

        // then
        assertScreenSnapshot(view, named: "detection")
    }

    @Test func `given groups and a selected group when loaded then the chips match the reference`() async {
        // given
        let view = await cameraGridScreen(
            cameras: .success(snapshotCameras()), reachable: true, activity: snapshotActivity(),
            groups: snapshotGroups(), today: snapshotToday(), storage: snapshotStorage(),
            selectedGroup: "Outdoor"
        )

        // then
        assertScreenSnapshot(view, named: "summary")
    }

    @Test func `given a group with no visible cameras when selected then the empty state matches the reference`() async {
        // given — "Attic" names a camera outside the loaded set, so the wall is empty while
        // `state == .loaded`; the chips must not describe a camera the filter just hid.
        let view = await cameraGridScreen(
            cameras: .success(snapshotCameras()), reachable: true, activity: snapshotActivity(),
            groups: [CameraGroup(name: "Attic", cameraNames: [CameraName("attic")], order: 2)] + snapshotGroups(),
            today: snapshotToday(), storage: snapshotStorage(),
            selectedGroup: "Attic"
        )

        // then
        assertScreenSnapshot(view, named: "empty-group")
    }

    @Test func `given unreachable cameras when offline then it matches the reference`() async {
        // given
        let view = await cameraGridScreen(
            cameras: .success(snapshotCameras()), reachable: false,
            today: snapshotToday(), storage: snapshotStorage()
        )

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
/// loading, so `await load()` settles the tiles, the offline treatment, and the offline chip before
/// capture. `reachable` picks whether the preview loader answers with bytes (online tiles) or `nil`
/// (offline tiles).
@MainActor
private func cameraGridScreen(
    cameras: Result<[Camera], CamerasError>,
    reachable: Bool = false,
    activity: [CameraActivity] = [],
    groups: [CameraGroup] = [],
    today: [String] = [],
    storage: RecordingStorage? = nil,
    selectedGroup: String? = nil
) async -> some View {
    let viewModel = CameraGridViewModel(
        observeCameras: ObserveCameras(
            getCameras: GetCameras(repository: FakeCamerasRepository(cameras)),
            observeCameraOrder: ObserveCameraOrder(repository: FakeSettingsRepository())
        ),
        getCameraActivity: GetCameraActivity(repository: FakeCameraActivityRepository(.success(activity))),
        observeCameraGroups: ObserveCameraGroups(repository: FakeCameraGroupsRepository(groups)),
        getTodayEventCounts: GetTodayEventCounts(
            repository: FakeTodayEventsRepository(.success(today)), now: { snapshotNow }
        ),
        observeRecordingStorage: ObserveRecordingStorage(
            repository: FakeRecordingStorageRepository(storage)
        ),
        imageLoader: FakeCameraImageLoader(image: reachable ? Data([0x01]) : nil)
    )
    await viewModel.load()
    viewModel.selectGroup(selectedGroup)

    return CameraGridView(
        viewModel: viewModel,
        onOpenSettings: {},
        // Unused: neither destination is built in a grid snapshot (no navigation happens).
        makeDetailViewModel: { CameraDetailViewModel(camera: $0, streamProvider: FakeCameraStreamProvider()) },
        cameraTimeline: { _ in EmptyView() }
    )
}

/// A day's worth of events for the summary card's TODAY column — 9 people + 5 cars = "14 events".
private func snapshotToday() -> [String] {
    Array(repeating: "person", count: 9) + Array(repeating: "car", count: 5)
}

/// A representative recordings-disk status: ~1.4 TB free of ~2 TB, kept 14 days.
private func snapshotStorage() -> RecordingStorage {
    RecordingStorage(freeBytes: 1_400_000_000_000, totalBytes: 2_000_000_000_000, retentionDays: 14)
}

/// A single in-progress **detection** (no alert) on `driveway` — proves a detection never promotes
/// a hero (`heroCamera` only reacts to an alert) and that the tile/chip badge renders amber.
private func snapshotDetectionOnly() -> [CameraActivity] {
    [CameraActivity(camera: CameraName("driveway"), label: "Car", severity: .detection, startedAt: snapshotNow)]
}

/// Two groups over `snapshotCameras()` — Outdoor (driveway, front door) and Indoor (backyard, garage).
private func snapshotGroups() -> [CameraGroup] {
    [
        CameraGroup(name: "Outdoor", cameraNames: [CameraName("driveway"), CameraName("front_door")], order: 0),
        CameraGroup(name: "Indoor", cameraNames: [CameraName("backyard"), CameraName("garage")], order: 1),
    ]
}
