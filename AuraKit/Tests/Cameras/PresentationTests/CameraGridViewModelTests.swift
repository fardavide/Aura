import Foundation
import Testing

import CamerasDomain
import CamerasEntities
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
        let sut = CameraGridViewModel(
            getCameras: GetCameras(repository: repository),
            imageLoader: FakeCameraImageLoader()
        )
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
        let sut = CameraGridViewModel(
            getCameras: GetCameras(repository: repository),
            imageLoader: FakeCameraImageLoader()
        )
        await sut.load()

        // when
        repository.result = .failure(.unreachable)
        await sut.load()

        // then
        #expect(sut.state == .loaded([enabledCamera("driveway")]))
    }

    @Test func `when requesting a preview then it delegates to the image loader`() async {
        // given
        let loader = FakeCameraImageLoader(image: Data([0x01]))
        let sut = CameraGridViewModel(
            getCameras: GetCameras(repository: FakeCamerasRepository(.success([]))),
            imageLoader: loader
        )

        // when
        let image = await sut.previewImage(for: enabledCamera("driveway"))

        // then
        #expect(image == Data([0x01]))
        #expect(loader.requested == [CameraName("driveway")])
    }
}

@MainActor
private func makeViewModel(_ result: Result<[Camera], CamerasError>) -> CameraGridViewModel {
    CameraGridViewModel(
        getCameras: GetCameras(repository: FakeCamerasRepository(result)),
        imageLoader: FakeCameraImageLoader()
    )
}

private func enabledCamera(_ name: String) -> Camera {
    Camera(name: CameraName(name), friendlyName: nil, isEnabled: true, streamNames: [])
}

