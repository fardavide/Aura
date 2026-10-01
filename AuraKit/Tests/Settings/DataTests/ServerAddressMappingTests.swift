import Foundation
import Testing

import CommonFrigate
import SettingsDomain
@testable import SettingsData

struct ServerAddressMappingTests {
    @Test func `given live transport when mapping then live playback reuses the selected API host`() {
        // given
        let server = ActiveServer(
            route: .local,
            address: ServerAddress(scheme: .https, host: "frigate.example.net", port: 8971),
            live: LiveConnectionSettings(scheme: .http, port: 1984),
            username: "admin", password: "hunter2"
        )

        // then
        #expect(server.liveBaseUrl?.absoluteString == "http://frigate.example.net:1984")
        #expect(ServerConfig(server).baseUrl.absoluteString == "https://frigate.example.net:8971")
    }
}
