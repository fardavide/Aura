import Foundation
import Testing

import CamerasDomain
import CamerasEntities
import CommonFrigate
import CommonNetwork
import TestDoubles
@testable import CamerasData

struct FrigateCameraActivityRepositoryTests {

    @Test func `given a 200 response when fetching activity then the in-progress items are decoded`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 200, body: Data(reviewJson.utf8))))

        // when
        let activity = try await sut.activeActivity()

        // then
        #expect(activity.map(\.camera) == [CameraName("front_door"), CameraName("driveway")])
    }

    @Test func `given credentials when fetching activity then a basic auth header is sent`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data(reviewJson.utf8)))
        let config = ServerConfig(
            scheme: .http, host: "frigate.test", port: 5000, username: "admin", password: "secret"
        )
        let sut = FrigateCameraActivityRepository(config: config, httpClient: http, now: { fixedNow })

        // when
        _ = try await sut.activeActivity()

        // then
        #expect(http.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func `given a 401 when fetching activity then it throws not authorized`() async {
        await expect(status: 401, mapsTo: .notAuthorized)
    }

    @Test func `given a 503 when fetching activity then it throws server unavailable`() async {
        await expect(status: 503, mapsTo: .serverUnavailable)
    }

    @Test func `given malformed json when fetching activity then it throws invalid data`() async {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 200, body: Data("not json".utf8))))

        // when - then
        await #expect(throws: CamerasError.invalidData) { try await sut.activeActivity() }
    }

    @Test func `given a transport failure when fetching activity then it throws unreachable`() async {
        // given
        let sut = makeSut(FakeHttpClient(.failure(URLError(.notConnectedToInternet))))

        // when - then
        await #expect(throws: CamerasError.unreachable) { try await sut.activeActivity() }
    }

    private func makeSut(_ http: FakeHttpClient) -> FrigateCameraActivityRepository {
        FrigateCameraActivityRepository(config: .test, httpClient: http, now: { fixedNow })
    }

    private func expect(status: Int, mapsTo error: CamerasError) async {
        let sut = makeSut(FakeHttpClient(.response(status: status, body: Data())))
        await #expect(throws: error) { try await sut.activeActivity() }
    }
}

private let fixedNow = Date(timeIntervalSince1970: 1_000_000)
