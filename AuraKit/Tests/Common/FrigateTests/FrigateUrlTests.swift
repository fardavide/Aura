import Foundation
import Testing

@testable import CommonFrigate

struct ServerConfigTests {

    @Test func `when reading the base url then it composes scheme host and port`() {
        // given
        let config = ServerConfig(
            scheme: .http,
            host: "frigate.local",
            port: 5000,
            username: nil,
            password: nil
        )

        // then
        #expect(config.baseUrl == URL(string: "http://frigate.local:5000")!)
    }

    @Test func `given the https scheme when reading the base url then it uses https`() {
        // given
        let config = ServerConfig(
            scheme: .https,
            host: "cam.example.com",
            port: 8971,
            username: nil,
            password: nil
        )

        // then
        #expect(config.baseUrl == URL(string: "https://cam.example.com:8971")!)
    }
}

struct FrigateUrlTests {
    private let base = URL(string: "http://frigate.local:5000")!

    @Test func `when building the config endpoint then it targets api config`() {
        #expect(
            FrigateEndpoint.config.url(base: base)
                == URL(string: "http://frigate.local:5000/api/config")!
        )
    }

    @Test func `when building the latest image url then it appends camera and height`() {
        // given - when
        let url = FrigateMediaUrl.latestImage(base: base, camera: "driveway", height: 320)

        // then
        #expect(url == URL(string: "http://frigate.local:5000/api/driveway/latest.jpg?height=320")!)
    }
}
