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
        let settings = FakeSettingsRepository()
        settings.savedCameraOrder = [CameraName("garage")]
        let sut = makeViewModel(
            cameras: .success([camera("attic"), camera("garage")]),
            settings: settings
        )

        // when
        await sut.load()

        // then
        #expect(sut.state == .loaded([camera("garage"), camera("attic")]))
    }

    @Test func `when moving a camera then the new order is persisted`() async {
        // given
        let settings = FakeSettingsRepository()
        let sut = makeViewModel(
            cameras: .success([camera("attic"), camera("driveway"), camera("garage")]),
            settings: settings
        )
        await sut.load()

        // when — move "garage" (index 2) to the front
        sut.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)

        // then
        #expect(sut.state == .loaded([camera("garage"), camera("attic"), camera("driveway")]))
        #expect(settings.savedCameraOrder == [CameraName("garage"), CameraName("attic"), CameraName("driveway")])
    }

    @Test func `given a fetch failure when loading then the state carries the error`() async {
        // given
        let sut = makeViewModel(cameras: .failure(.notAuthorized))

        // when
        await sut.load()

        // then
        #expect(sut.state == .failed(.notAuthorized))
    }
}

private func camera(_ name: String) -> Camera {
    Camera(name: CameraName(name), friendlyName: nil, isEnabled: true, streamNames: [])
}

@MainActor
private func makeViewModel(
    cameras: Result<[Camera], CamerasError>,
    settings: FakeSettingsRepository = FakeSettingsRepository()
) -> CameraOrderViewModel {
    CameraOrderViewModel(
        getCameras: GetCameras(repository: FakeCamerasRepository(cameras)),
        loadCameraOrder: LoadCameraOrder(repository: settings),
        saveCameraOrder: SaveCameraOrder(repository: settings)
    )
}


