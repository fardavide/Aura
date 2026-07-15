import Foundation
import Testing

import CamerasEntities
import SettingsDomain
import TestDoubles
@testable import CamerasDomain

struct CamerasDomainTests {

    // MARK: CameraName

    @Test func `when comparing camera names with the same value then they are equal`() {
        // given - when
        let a = CameraName("driveway")
        let b = CameraName("driveway")

        // then
        #expect(a == b)
    }

    @Test func `when sorting camera names then they are ordered by value`() {
        // given - when
        let sorted = [CameraName("garage"), CameraName("driveway")].sorted()

        // then
        #expect(sorted == [CameraName("driveway"), CameraName("garage")])
    }

    // MARK: Camera order

    @Test func `given a saved order when sorting then cameras follow it`() {
        // given
        let cameras = [
            camera("attic", isEnabled: true),
            camera("driveway", isEnabled: true),
            camera("garage", isEnabled: true),
        ]

        // when
        let sorted = cameras.sorted(byPreference: [
            CameraName("garage"), CameraName("attic"), CameraName("driveway"),
        ])

        // then
        #expect(sorted.map(\.name) == [CameraName("garage"), CameraName("attic"), CameraName("driveway")])
    }

    @Test func `given cameras missing from the saved order when sorting then they keep their relative order after it`() {
        // given
        let cameras = [
            camera("attic", isEnabled: true),
            camera("driveway", isEnabled: true),
            camera("garage", isEnabled: true),
        ]

        // when
        let sorted = cameras.sorted(byPreference: [CameraName("garage")])

        // then
        #expect(sorted.map(\.name) == [CameraName("garage"), CameraName("attic"), CameraName("driveway")])
    }

    @Test func `given stale names in the saved order when sorting then they are ignored`() {
        // given
        let cameras = [camera("attic", isEnabled: true), camera("garage", isEnabled: true)]

        // when
        let sorted = cameras.sorted(byPreference: [CameraName("removed"), CameraName("garage")])

        // then
        #expect(sorted.map(\.name) == [CameraName("garage"), CameraName("attic")])
    }

    // MARK: GetCameras

    @Test func `given a disabled camera when getting cameras then it is excluded`() async throws {
        // given
        let getCameras = GetCameras(repository: FakeCamerasRepository(.success([
            camera("driveway", isEnabled: true),
            camera("garage", isEnabled: false),
        ])))

        // when
        let result = try await getCameras.execute()

        // then
        #expect(result.map(\.name) == [CameraName("driveway")])
    }

    // MARK: ObserveCameras

    @Test func `given a saved order when observing cameras then the sorted list is emitted`() async throws {
        // given
        let settings = FakeSettingsRepository()
        settings.savedCameraOrder = [CameraName("garage")]
        let observeCameras = makeObserveCameras(
            cameras: [camera("attic", isEnabled: true), camera("garage", isEnabled: true)],
            settings: settings
        )

        // when
        var iterator = try await observeCameras.execute().makeAsyncIterator()

        // then
        #expect(await iterator.next()?.map(\.name) == [CameraName("garage"), CameraName("attic")])
    }

    @Test func `given an observer when the order changes then the re-sorted list is emitted`() async throws {
        // given
        let settings = FakeSettingsRepository()
        let observeCameras = makeObserveCameras(
            cameras: [camera("attic", isEnabled: true), camera("garage", isEnabled: true)],
            settings: settings
        )
        var iterator = try await observeCameras.execute().makeAsyncIterator()
        _ = await iterator.next()

        // when
        settings.saveCameraOrder([CameraName("garage"), CameraName("attic")])

        // then
        #expect(await iterator.next()?.map(\.name) == [CameraName("garage"), CameraName("attic")])
    }

    @Test func `given a failing repository when observing cameras then it propagates the error`() async {
        // given
        let observeCameras = ObserveCameras(
            getCameras: GetCameras(repository: FakeCamerasRepository(.failure(.unreachable))),
            observeCameraOrder: ObserveCameraOrder(repository: FakeSettingsRepository())
        )

        // when - then
        await #expect(throws: CamerasError.unreachable) {
            _ = try await observeCameras.execute()
        }
    }

    // MARK: GetCameraActivity

    @Test func `given activity on several cameras when getting activity then each is keyed by its camera`() async throws {
        // given
        let getActivity = GetCameraActivity(repository: FakeCameraActivityRepository(.success([
            activity("driveway", label: "Person", severity: .alert, startedAt: 100),
            activity("garage", label: "Car", severity: .detection, startedAt: 100),
        ])))

        // when
        let result = try await getActivity.execute()

        // then
        #expect(result[CameraName("driveway")]?.severity == .alert)
        #expect(result[CameraName("garage")]?.label == "Car")
    }

    @Test func `given several items for one camera when getting activity then the most recent wins`() async throws {
        // given
        let getActivity = GetCameraActivity(repository: FakeCameraActivityRepository(.success([
            activity("driveway", label: "Car", severity: .detection, startedAt: 100),
            activity("driveway", label: "Person", severity: .alert, startedAt: 200),
        ])))

        // when
        let result = try await getActivity.execute()

        // then
        #expect(result.count == 1)
        #expect(result[CameraName("driveway")]?.label == "Person")
    }
}

private func makeObserveCameras(cameras: [Camera], settings: FakeSettingsRepository) -> ObserveCameras {
    ObserveCameras(
        getCameras: GetCameras(repository: FakeCamerasRepository(.success(cameras))),
        observeCameraOrder: ObserveCameraOrder(repository: settings)
    )
}

private func camera(_ name: String, isEnabled: Bool) -> Camera {
    Camera(name: CameraName(name), friendlyName: nil, isEnabled: isEnabled, streamNames: [])
}

private func activity(
    _ camera: String,
    label: String,
    severity: CameraActivity.Severity,
    startedAt: TimeInterval
) -> CameraActivity {
    CameraActivity(
        camera: CameraName(camera),
        label: label,
        severity: severity,
        startedAt: Date(timeIntervalSince1970: startedAt)
    )
}

