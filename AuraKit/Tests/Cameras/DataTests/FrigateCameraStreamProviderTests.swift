import Foundation
import Testing

import CamerasDomain
import CommonFrigate
import CamerasEntities
@testable import CamerasData

struct FrigateCameraStreamProviderTests {

    @Test func `given a camera with a stream when resolving then it builds the proxied go2rtc url`() {
        // given
        let sut = FrigateCameraStreamProvider(config: .test)

        // when
        let source = sut.streamSource(for: camera(streamNames: ["driveway", "driveway_sub"]))

        // then
        #expect(
            source?.url
                == URL(string: "http://frigate.test:5000/api/go2rtc/api/stream.m3u8?src=driveway")!
        )
        #expect(source?.headers.isEmpty == true)
    }

    @Test func `given credentials when resolving a stream then a basic auth header is attached`() {
        // given
        let config = ServerConfig(
            scheme: .http, host: "frigate.test", port: 5000, username: "admin", password: "secret"
        )
        let sut = FrigateCameraStreamProvider(config: config)

        // when
        let source = sut.streamSource(for: camera(streamNames: ["driveway"]))

        // then
        #expect(source?.headers["Authorization"] == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func `given a camera with no streams when resolving then it is nil`() {
        #expect(FrigateCameraStreamProvider(config: .test).streamSource(for: camera(streamNames: [])) == nil)
    }
}

private func camera(streamNames: [String]) -> Camera {
    Camera(name: CameraName("driveway"), friendlyName: nil, isEnabled: true, streamNames: streamNames)
}
