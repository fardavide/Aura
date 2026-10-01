import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import CommonFrigate
import TestDoubles
@testable import CamerasData

struct FrigateCameraStreamProviderTests {

    @Test func `given a separate live endpoint when resolving then it uses direct go2rtc HLS`() throws {
        // given
        let base = try #require(URL(string: "https://live.example.test:1984"))
        let sut = FrigateCameraStreamProvider(config: .test, go2rtcBaseUrl: base)

        // when
        let source = sut.streamSource(for: camera(streamNames: ["front_garden_1", "front_garden_sub"]))

        // then
        #expect(source?.url.absoluteString == "https://live.example.test:1984/api/stream.m3u8?src=front_garden_1")
    }

    @Test(arguments: ["frigate.test", "live.example.test"])
    func `given Frigate credentials when using direct go2rtc then no authorization header is forwarded`(host: String) throws {
        // given
        let base = try #require(URL(string: "http://\(host):1984"))
        let config = ServerConfig(
            scheme: .http, host: "frigate.test", port: 5000, username: "admin", password: "secret"
        )
        let sut = FrigateCameraStreamProvider(config: config, go2rtcBaseUrl: base)

        // when
        let source = try #require(sut.streamSource(for: camera(streamNames: ["front_garden_1"])))

        // then
        #expect(source.headers.isEmpty)
    }

    @Test func `given a camera with a stream when resolving then it builds the proxied go2rtc url`() {
        // given
        let sut = FrigateCameraStreamProvider(config: .test, go2rtcBaseUrl: nil)

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
        let sut = FrigateCameraStreamProvider(config: config, go2rtcBaseUrl: nil)

        // when
        let source = sut.streamSource(for: camera(streamNames: ["driveway"]))

        // then
        #expect(source?.headers["Authorization"] == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func `given a camera with no streams when resolving then it is nil`() {
        #expect(FrigateCameraStreamProvider(config: .test, go2rtcBaseUrl: nil).streamSource(for: camera(streamNames: [])) == nil)
    }
}

private func camera(streamNames: [String]) -> Camera {
    Camera(name: CameraName("driveway"), friendlyName: nil, isEnabled: true, streamNames: streamNames)
}
