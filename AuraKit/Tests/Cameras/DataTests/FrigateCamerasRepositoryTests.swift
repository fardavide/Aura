import Foundation
import Testing

import CamerasDomain
import CommonFrigate
import CommonNetwork
@testable import CamerasData

struct FrigateCamerasRepositoryTests {

    @Test func `given a 200 response when fetching cameras then they are decoded`() async throws {
        // given
        let sut = FrigateCamerasRepository(
            config: .test,
            httpClient: FakeHttpClient(.response(status: 200, body: Data(configJson.utf8)))
        )

        // when
        let cameras = try await sut.cameras()

        // then
        #expect(cameras.map(\.name) == [
            CameraName("driveway"), CameraName("garage"), CameraName("porch"),
        ])
    }

    @Test func `given credentials when fetching cameras then a basic auth header is sent`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data(configJson.utf8)))
        let config = ServerConfig(
            scheme: .http, host: "frigate.test", port: 5000, username: "admin", password: "secret"
        )
        let sut = FrigateCamerasRepository(config: config, httpClient: http)

        // when
        _ = try await sut.cameras()

        // then
        #expect(http.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func `given a 401 when fetching cameras then it throws not authorized`() async {
        await expect(status: 401, mapsTo: .notAuthorized)
    }

    @Test func `given a 403 when fetching cameras then it throws not authorized`() async {
        await expect(status: 403, mapsTo: .notAuthorized)
    }

    @Test func `given a 503 when fetching cameras then it throws server unavailable`() async {
        await expect(status: 503, mapsTo: .serverUnavailable)
    }

    @Test func `given malformed json when fetching cameras then it throws invalid data`() async {
        // given
        let sut = FrigateCamerasRepository(
            config: .test,
            httpClient: FakeHttpClient(.response(status: 200, body: Data("not json".utf8)))
        )

        // when - then
        await #expect(throws: CamerasError.invalidData) { try await sut.cameras() }
    }

    @Test func `given a transport failure when fetching cameras then it throws unreachable`() async {
        // given
        let sut = FrigateCamerasRepository(
            config: .test,
            httpClient: FakeHttpClient(.failure(URLError(.notConnectedToInternet)))
        )

        // when - then
        await #expect(throws: CamerasError.unreachable) { try await sut.cameras() }
    }

    private func expect(status: Int, mapsTo error: CamerasError) async {
        let sut = FrigateCamerasRepository(
            config: .test,
            httpClient: FakeHttpClient(.response(status: status, body: Data()))
        )
        await #expect(throws: error) { try await sut.cameras() }
    }
}
