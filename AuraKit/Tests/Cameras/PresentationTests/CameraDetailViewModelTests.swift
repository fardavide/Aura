import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import TestDoubles
@testable import CamerasPresentation

@MainActor
struct CameraDetailViewModelTests {

    @Test func `given a camera with a stream when created then it plays that source`() {
        // given
        let source = CameraStreamSource(url: URL(string: "http://host/stream.m3u8?src=a")!, headers: [:])
        let sut = CameraDetailViewModel(
            camera: camera("driveway", friendly: "Driveway"),
            streamProvider: FakeCameraStreamProvider(source)
        )

        // then
        #expect(sut.state == .playing(source))
        #expect(sut.title == "Driveway")
    }

    @Test func `given a camera with no stream when created then it is unavailable`() {
        // given
        let sut = CameraDetailViewModel(
            camera: camera("garage", friendly: nil),
            streamProvider: FakeCameraStreamProvider(nil)
        )

        // then
        #expect(sut.state == .unavailable)
        #expect(sut.title == "garage")
    }
}

private func camera(_ name: String, friendly: String?) -> Camera {
    Camera(name: CameraName(name), friendlyName: friendly, isEnabled: true, streamNames: [])
}

