import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import SettingsDomain
import TestDoubles
@testable import CamerasPresentation

@MainActor
struct CameraGridViewModelTests {

    @Test func `given enabled cameras when loading then the state is loaded`() async {
        // given
        let sut = makeViewModel(.success([enabledCamera("driveway")]))

        // when
        await sut.load()

        // then
        #expect(sut.state == .loaded([enabledCamera("driveway")]))
    }

    @Test func `given no cameras when loading then the state is empty`() async {
        // given
        let sut = makeViewModel(.success([]))

        // when
        await sut.load()

        // then
        #expect(sut.state == .empty)
    }

    @Test func `given a failure when loading then the state carries the error`() async {
        // given
        let sut = makeViewModel(.failure(.notAuthorized))

        // when
        await sut.load()

        // then
        #expect(sut.state == .failed(.notAuthorized))
    }

    @Test func `given a loaded state when loading again then the fresh content is shown`() async {
        // given
        let repository = FakeCamerasRepository(.success([enabledCamera("driveway")]))
        let sut = makeViewModel(repository: repository)
        await sut.load()

        // when
        repository.result = .success([enabledCamera("garage")])
        await sut.load()

        // then
        #expect(sut.state == .loaded([enabledCamera("garage")]))
    }

    @Test func `given a loaded state when a refresh fails then the last good content is kept`() async {
        // given
        let repository = FakeCamerasRepository(.success([enabledCamera("driveway")]))
        let sut = makeViewModel(repository: repository)
        await sut.load()

        // when
        repository.result = .failure(.unreachable)
        await sut.load()

        // then
        #expect(sut.state == .loaded([enabledCamera("driveway")]))
    }

    @Test func `given loaded cameras when the order changes then the grid re-sorts`() async {
        // given
        let settings = FakeSettingsRepository()
        let sut = makeViewModel(
            .success([enabledCamera("attic"), enabledCamera("garage")]),
            settings: settings
        )
        await sut.load()

        // when
        settings.saveCameraOrder([CameraName("garage"), CameraName("attic")])

        // then
        let resorted: CameraGridViewModel.State = .loaded([enabledCamera("garage"), enabledCamera("attic")])
        for _ in 0..<100 where sut.state != resorted {
            await Task.yield()
        }
        #expect(sut.state == resorted)
    }

    @Test func `given reachable cameras when loading then their previews are loaded from the image loader`() async {
        // given
        let loader = FakeCameraImageLoader(image: Data([0x01]))
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])), imageLoader: loader
        )

        // when
        await sut.load()

        // then
        #expect(sut.previewImage(for: enabledCamera("driveway")) == Data([0x01]))
        #expect(loader.requested == [CameraName("driveway")])
    }

    // MARK: Activity

    @Test func `given active review items when loading then the grid exposes each camera's activity`() async {
        // given
        let activity = CameraActivity(
            camera: CameraName("driveway"), label: "Person", severity: .alert,
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            activity: FakeCameraActivityRepository(.success([activity]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.activity(for: enabledCamera("driveway")) == activity)
    }

    @Test func `given the activity fetch fails when loading then the grid still loads without badges`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            activity: FakeCameraActivityRepository(.failure(.unreachable))
        )

        // when
        await sut.load()

        // then
        #expect(sut.state == .loaded([enabledCamera("driveway")]))
        #expect(sut.activity(for: enabledCamera("driveway")) == nil)
    }

    // MARK: Live / offline counts

    @Test func `given a preview resolves when loading then the camera is not offline`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            imageLoader: FakeCameraImageLoader(image: Data([0x01]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.offlineCount == 0)
        #expect(sut.isOffline(enabledCamera("driveway")) == false)
    }

    @Test func `given a preview fails to load when loading then the camera is counted offline`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            imageLoader: FakeCameraImageLoader(image: nil)
        )

        // when
        await sut.load()

        // then
        #expect(sut.offlineCount == 1)
        #expect(sut.isOffline(enabledCamera("driveway")) == true)
    }

    // MARK: Refresh

    @Test func `given loaded cameras when refreshing then the stills are re-fetched`() async {
        // given
        let loader = FakeCameraImageLoader(image: Data([0x01]))
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])), imageLoader: loader
        )
        await sut.load()

        // when
        loader.image = Data([0x02])
        await sut.refresh()

        // then
        #expect(sut.previewImage(for: enabledCamera("driveway")) == Data([0x02]))
    }

    // MARK: Groups & filtering

    @Test func `given groups when loading then they are exposed sorted by order`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            groups: FakeCameraGroupsRepository([
                group("Indoor", ["kitchen"], order: 1),
                group("Outdoor", ["driveway"], order: 0),
            ])
        )

        // when
        await sut.load()

        // then
        #expect(sut.groups.map(\.name) == ["Outdoor", "Indoor"])
    }

    @Test func `given a selected group when reading visible cameras then only its members show`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("kitchen")])),
            groups: FakeCameraGroupsRepository([group("Indoor", ["kitchen"])])
        )
        await sut.load()

        // when
        sut.selectGroup("Indoor")

        // then
        #expect(sut.visibleCameras.map(\.name) == [CameraName("kitchen")])
    }

    @Test func `given no group selected when reading visible cameras then all show`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("kitchen")]))
        )
        await sut.load()

        // then
        #expect(sut.visibleCameras.count == 2)
    }

    @Test func `given a selected group no longer present when reading visible cameras then all show`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("kitchen")]))
        )
        await sut.load()

        // when — a group that isn't in the loaded set
        sut.selectGroup("Removed")

        // then
        #expect(sut.visibleCameras.count == 2)
    }

    // MARK: Right Now

    @Test func `given an alert and a detection when reading right now then the alert wins`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("front_door")])),
            activity: FakeCameraActivityRepository(.success([
                activity("driveway", label: "Car", severity: .detection, startedAt: 200),
                activity("front_door", label: "Person", severity: .alert, startedAt: 100),
            ]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.rightNow?.camera.name == CameraName("front_door"))
        #expect(sut.rightNow?.severity == .alert)
        #expect(sut.rightNow?.label == "Person")
    }

    @Test func `given two detections when reading right now then the most recent wins`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("garage")])),
            activity: FakeCameraActivityRepository(.success([
                activity("driveway", label: "Car", severity: .detection, startedAt: 100),
                activity("garage", label: "Dog", severity: .detection, startedAt: 200),
            ]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.rightNow?.camera.name == CameraName("garage"))
    }

    @Test func `given no activity when reading right now then it is quiet`() async {
        // given
        let sut = makeViewModel(repository: FakeCamerasRepository(.success([enabledCamera("driveway")])))

        // when
        await sut.load()

        // then
        #expect(sut.rightNow == nil)
    }

    // MARK: Hero

    @Test func `given an alert and a detection when reading the hero camera then the alerting camera is the hero`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("front_door")])),
            activity: FakeCameraActivityRepository(.success([
                activity("driveway", label: "Car", severity: .detection, startedAt: 200),
                activity("front_door", label: "Person", severity: .alert, startedAt: 100),
            ]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.heroCamera?.name == CameraName("front_door"))
    }

    @Test func `given only detections when reading the hero camera then the first camera is the hero`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("garage")])),
            activity: FakeCameraActivityRepository(.success([
                activity("garage", label: "Dog", severity: .detection, startedAt: 200),
            ]))
        )

        // when
        await sut.load()

        // then — pins the difference from `rightNow`, which *would* pick `garage` (its only activity)
        #expect(sut.heroCamera?.name == CameraName("driveway"))
    }

    @Test func `given no activity when reading the hero camera then the first camera is the hero`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("garage")]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.heroCamera?.name == CameraName("driveway"))
    }

    @Test func `given two alerts when reading the hero camera then the most recent one wins`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("front_door")])),
            activity: FakeCameraActivityRepository(.success([
                activity("driveway", label: "Person", severity: .alert, startedAt: 100),
                activity("front_door", label: "Person", severity: .alert, startedAt: 200),
            ]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.heroCamera?.name == CameraName("front_door"))
    }

    @Test func `given a selected group when reading the hero camera then an alert outside the group is ignored`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("front_door")])),
            activity: FakeCameraActivityRepository(.success([
                activity("front_door", label: "Person", severity: .alert, startedAt: 100),
            ])),
            groups: FakeCameraGroupsRepository([group("Outdoor", ["driveway"])])
        )
        await sut.load()

        // when
        sut.selectGroup("Outdoor")

        // then
        #expect(sut.heroCamera?.name == CameraName("driveway"))
    }

    @Test func `given no cameras when reading the hero camera then there is none`() async {
        // given
        let sut = makeViewModel(repository: FakeCamerasRepository(.success([])))

        // when
        await sut.load()

        // then
        #expect(sut.heroCamera == nil)
    }

    @Test func `given an alert when reading the wall cameras then the hero leads and the rest keep their order`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([
                enabledCamera("driveway"), enabledCamera("front_door"), enabledCamera("garage"),
            ])),
            activity: FakeCameraActivityRepository(.success([
                activity("front_door", label: "Person", severity: .alert, startedAt: 100),
            ]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.wallCameras.map(\.name) == [
            CameraName("front_door"), CameraName("driveway"), CameraName("garage"),
        ])
    }

    @Test func `given a selected group when reading the wall cameras then only its members are listed`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("kitchen")])),
            groups: FakeCameraGroupsRepository([group("Indoor", ["kitchen"])])
        )
        await sut.load()

        // when
        sut.selectGroup("Indoor")

        // then
        #expect(sut.wallCameras.map(\.name) == [CameraName("kitchen")])
    }

    // MARK: Chips

    @Test func `given today's events when reading the today chip then it counts them`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            today: FakeTodayEventsRepository(.success(
                Array(repeating: "person", count: 9) + Array(repeating: "car", count: 5)
            ))
        )

        // when
        await sut.load()

        // then
        #expect(sut.todayChipText == "14 today")
    }

    @Test func `given no tally when reading the today chip then there is none`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            today: FakeTodayEventsRepository(.failure(.unreachable))
        )

        // when
        await sut.load()

        // then
        #expect(sut.todayChipText == nil)
    }

    @Test func `given labelled events when reading the today breakdown then the two most frequent are listed`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            today: FakeTodayEventsRepository(.success(
                Array(repeating: "person", count: 9) + Array(repeating: "car", count: 5)
            ))
        )

        // when
        await sut.load()

        // then
        #expect(sut.todayBreakdownText == "9 person · 5 car")
    }

    @Test func `given no labelled events when reading the today breakdown then there is none`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            today: FakeTodayEventsRepository(.success([]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.todayBreakdownText == nil)
    }

    @Test func `given a retention when reading the retention chip then it names the days kept`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            storage: FakeRecordingStorageRepository(
                RecordingStorage(freeBytes: 1_000, totalBytes: 2_000, retentionDays: 14)
            )
        )

        // when
        await sut.load()

        // then
        #expect(sut.retentionChipText == "14 days kept")
    }

    @Test func `given a one day retention when reading the retention chip then the day is singular`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            storage: FakeRecordingStorageRepository(
                RecordingStorage(freeBytes: 1_000, totalBytes: 2_000, retentionDays: 1)
            )
        )

        // when
        await sut.load()

        // then
        #expect(sut.retentionChipText == "1 day kept")
    }

    @Test func `given storage without a retention when reading the retention chip then there is none`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            storage: FakeRecordingStorageRepository(
                RecordingStorage(freeBytes: 1_000, totalBytes: 2_000, retentionDays: nil)
            )
        )

        // when
        await sut.load()

        // then
        #expect(sut.retentionChipText == nil)
    }

    @Test func `given an unreachable camera when reading the offline chip then it counts it`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            imageLoader: FakeCameraImageLoader(image: nil)
        )

        // when
        await sut.load()

        // then
        #expect(sut.offlineChipText == "1 offline")
    }

    @Test func `given every camera reachable when reading the offline chip then there is none`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            imageLoader: FakeCameraImageLoader(image: Data([0x01]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.offlineChipText == nil)
    }

    @Test func `given a selected group when reading right now then activity outside the group is ignored`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("front_door")])),
            activity: FakeCameraActivityRepository(.success([
                activity("front_door", label: "Person", severity: .alert, startedAt: 100),
            ])),
            groups: FakeCameraGroupsRepository([group("Outdoor", ["driveway"])])
        )
        await sut.load()

        // when
        sut.selectGroup("Outdoor")

        // then
        #expect(sut.rightNow == nil)
    }

    @Test func `given a selected group when reading the offline chip then only its members are counted`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway"), enabledCamera("kitchen")])),
            groups: FakeCameraGroupsRepository([group("Indoor", ["kitchen"])]),
            imageLoader: FakeCameraImageLoader(image: nil)
        )
        await sut.load()

        // when
        sut.selectGroup("Indoor")

        // then
        #expect(sut.offlineChipText == "1 offline")
    }

    @Test func `given no summary data when reading whether there are chips then there are none`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            today: FakeTodayEventsRepository(.failure(.unreachable)),
            storage: FakeRecordingStorageRepository(nil),
            imageLoader: FakeCameraImageLoader(image: Data([0x01]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.hasSummaryChips == false)
    }

    // MARK: Summary card

    @Test func `given today's events when loading then the tally is exposed`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            today: FakeTodayEventsRepository(.success(["person", "car", "person"]))
        )

        // when
        await sut.load()

        // then
        #expect(sut.todayEvents?.total == 3)
        #expect(sut.todayEvents?.breakdown.first == EventCount.LabelCount(label: "person", count: 2))
    }

    @Test func `given storage when loading then it is exposed`() async {
        // given
        let storage = RecordingStorage(freeBytes: 1_000, totalBytes: 2_000, retentionDays: 14)
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            storage: FakeRecordingStorageRepository(storage)
        )

        // when
        await sut.load()

        // then
        #expect(sut.storage == storage)
    }

    @Test func `given the summary fetches fail when loading then the grid still loads`() async {
        // given
        let sut = makeViewModel(
            repository: FakeCamerasRepository(.success([enabledCamera("driveway")])),
            groups: FakeCameraGroupsRepository([]),
            today: FakeTodayEventsRepository(.failure(.unreachable)),
            storage: FakeRecordingStorageRepository(nil)
        )

        // when
        await sut.load()

        // then
        #expect(sut.state == .loaded([enabledCamera("driveway")]))
        #expect(sut.groups.isEmpty)
        #expect(sut.todayEvents == nil)
        #expect(sut.storage == nil)
    }
}

@MainActor
private func makeViewModel(
    _ result: Result<[Camera], CamerasError>,
    settings: FakeSettingsRepository = FakeSettingsRepository()
) -> CameraGridViewModel {
    makeViewModel(repository: FakeCamerasRepository(result), settings: settings)
}

@MainActor
private func makeViewModel(
    repository: FakeCamerasRepository,
    settings: FakeSettingsRepository = FakeSettingsRepository(),
    activity: FakeCameraActivityRepository = FakeCameraActivityRepository(.success([])),
    groups: FakeCameraGroupsRepository = FakeCameraGroupsRepository([]),
    today: FakeTodayEventsRepository = FakeTodayEventsRepository(.success([])),
    storage: FakeRecordingStorageRepository = FakeRecordingStorageRepository(),
    imageLoader: FakeCameraImageLoader = FakeCameraImageLoader()
) -> CameraGridViewModel {
    CameraGridViewModel(
        observeCameras: ObserveCameras(
            getCameras: GetCameras(repository: repository),
            observeCameraOrder: ObserveCameraOrder(repository: settings)
        ),
        getCameraActivity: GetCameraActivity(repository: activity),
        observeCameraGroups: ObserveCameraGroups(repository: groups),
        getTodayEventCounts: GetTodayEventCounts(repository: today, now: { fixedNow }),
        observeRecordingStorage: ObserveRecordingStorage(repository: storage),
        imageLoader: imageLoader
    )
}

private let fixedNow = Date(timeIntervalSince1970: 1_000_000)

private func enabledCamera(_ name: String) -> Camera {
    Camera(name: CameraName(name), friendlyName: nil, isEnabled: true, streamNames: [])
}

private func group(_ name: String, _ cameras: [String], order: Int = 0) -> CameraGroup {
    CameraGroup(name: name, cameraNames: cameras.map(CameraName.init), order: order)
}

private func activity(
    _ camera: String, label: String, severity: CameraActivity.Severity, startedAt: TimeInterval
) -> CameraActivity {
    CameraActivity(
        camera: CameraName(camera), label: label, severity: severity,
        startedAt: Date(timeIntervalSince1970: startedAt)
    )
}
