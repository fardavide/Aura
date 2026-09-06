import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import SettingsDomain
import TestDoubles
@testable import SettingsPresentation

@MainActor
struct CameraOrderViewModelTests {

    @Test func `given cameras and a saved order when loading then the effective order is shown`() async {
        // given
        let scenario = Scenario(
            cameras: .success([camera("attic"), camera("garage")]),
            savedOrder: [CameraName("garage")]
        )

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.state == .loaded([camera("garage"), camera("attic")]))
    }

    @Test func `when moving a camera then the new order is persisted`() async {
        // given
        let scenario = Scenario(cameras: .success([camera("attic"), camera("driveway"), camera("garage")]))
        await scenario.sut.load()

        // when — move "garage" (index 2) to the front
        scenario.sut.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        // then
        #expect(scenario.sut.state == .loaded([camera("garage"), camera("attic"), camera("driveway")]))
        #expect(scenario.settings.savedCameraOrder == [CameraName("garage"), CameraName("attic"), CameraName("driveway")])
    }

    @Test func `given saved names not shown in the editor when moving then they survive after the visible ones`() async {
        // given — "cellar" is saved (e.g. currently disabled on the server) but not listed
        let scenario = Scenario(
            cameras: .success([camera("attic"), camera("garage")]),
            savedOrder: [CameraName("cellar")]
        )
        await scenario.sut.load()

        // when
        scenario.sut.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        // then
        #expect(scenario.settings.savedCameraOrder == [CameraName("garage"), CameraName("attic"), CameraName("cellar")])
    }

    @Test func `given a fetch failure when loading then the state carries the error`() async {
        // given
        let scenario = Scenario(cameras: .failure(.notAuthorized))

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.state == .failed(.notAuthorized))
    }

    @Test func `given loaded cameras when a reload fails then the list is kept`() async {
        // given
        let scenario = Scenario(cameras: .success([camera("attic"), camera("garage")]))
        await scenario.sut.load()

        // when
        scenario.cameras.result = .failure(.unreachable)
        await scenario.sut.load()

        // then
        #expect(scenario.sut.state == .loaded([camera("attic"), camera("garage")]))
    }
}

private func camera(_ name: String) -> Camera {
    Camera(name: CameraName(name), friendlyName: nil, isEnabled: true, streamNames: [])
}

@MainActor
private struct Scenario {
    let cameras: FakeCamerasRepository
    let settings: FakeSettingsRepository
    let sut: CameraOrderViewModel

    init(cameras: Result<[Camera], CamerasError>, savedOrder: [CameraName] = []) {
        self.cameras = FakeCamerasRepository(cameras)
        settings = FakeSettingsRepository()
        settings.savedCameraOrder = savedOrder
        sut = CameraOrderViewModel(
            getCameras: GetCameras(repository: self.cameras),
            loadCameraOrder: LoadCameraOrder(repository: settings),
            saveCameraOrder: SaveCameraOrder(repository: settings)
        )
    }
}

