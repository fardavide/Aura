import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import CommonFrigate
import CommonNetwork
import TestDoubles
@testable import CamerasData

struct FrigateCameraImageLoaderTests {

    @Test func `given a 200 image response when loading a preview then it returns the bytes`() async {
        // given
        let bytes = Data([0xFF, 0xD8, 0xFF])
        let sut = FrigateCameraImageLoader(
            config: .test,
            httpClient: FakeHttpClient(.response(status: 200, body: bytes))
        )

        // when
        let image = await sut.previewImage(for: CameraName("driveway"))

        // then
        #expect(image == bytes)
    }

    @Test func `given a non-success status when loading a preview then it returns nil`() async {
        // given
        let sut = FrigateCameraImageLoader(
            config: .test,
            httpClient: FakeHttpClient(.response(status: 404, body: Data()))
        )

        // when - then
        #expect(await sut.previewImage(for: CameraName("driveway")) == nil)
    }

    @Test func `given a transport failure when loading a preview then it returns nil`() async {
        // given
        let sut = FrigateCameraImageLoader(
            config: .test,
            httpClient: FakeHttpClient(.failure(URLError(.timedOut)))
        )

        // when - then
        #expect(await sut.previewImage(for: CameraName("driveway")) == nil)
    }

    @Test func `when loading a preview then the request carries a bounded timeout`() async {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data()))
        let sut = FrigateCameraImageLoader(config: .test, httpClient: http)

        // when
        _ = await sut.previewImage(for: CameraName("driveway"))

        // then
        #expect(http.lastRequest?.timeoutInterval == 15)
    }

    @Test func `given credentials when loading a preview then it targets latest.jpg with auth`() async {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data()))
        let config = ServerConfig(
            scheme: .http, host: "frigate.test", port: 5000, username: "admin", password: "secret"
        )
        let sut = FrigateCameraImageLoader(config: config, httpClient: http, height: 320)

        // when
        _ = await sut.previewImage(for: CameraName("driveway"))

        // then
        #expect(
            http.lastRequest?.url
                == URL(string: "http://frigate.test:5000/api/driveway/latest.jpg?height=320")!
        )
        #expect(http.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Basic YWRtaW46c2VjcmV0")
    }
}
