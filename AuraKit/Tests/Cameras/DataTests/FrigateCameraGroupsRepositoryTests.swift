import Foundation
import Testing

import CamerasDomain
import CommonFrigate
import CommonNetwork
import TestDoubles
@testable import CamerasData

struct FrigateCameraGroupsRepositoryTests {

    @Test func `given a 200 response when fetching groups then they are decoded`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 200, body: Data(groupsConfigJson.utf8))))

        // when
        let groups = try await sut.groups()

        // then
        #expect(Set(groups.map(\.name)) == ["Outdoor", "Indoor", "Overview"])
    }

    @Test func `given credentials when fetching groups then a basic auth header is sent`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data(groupsConfigJson.utf8)))
        let config = ServerConfig(
            scheme: .http, host: "frigate.test", port: 5000, username: "admin", password: "secret"
        )
        let sut = FrigateCameraGroupsRepository(config: config, httpClient: http)

        // when
        _ = try await sut.groups()

        // then
        #expect(http.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func `given a 401 when fetching groups then it throws not authorized`() async {
        await expect(status: 401, mapsTo: .notAuthorized)
    }

    @Test func `given a 503 when fetching groups then it throws server unavailable`() async {
        await expect(status: 503, mapsTo: .serverUnavailable)
    }

    @Test func `given malformed json when fetching groups then it throws invalid data`() async {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 200, body: Data("not json".utf8))))

        // when - then
        await #expect(throws: CamerasError.invalidData) { try await sut.groups() }
    }

    @Test func `given a transport failure when fetching groups then it throws unreachable`() async {
        // given
        let sut = makeSut(FakeHttpClient(.failure(URLError(.notConnectedToInternet))))

        // when - then
        await #expect(throws: CamerasError.unreachable) { try await sut.groups() }
    }

    private func makeSut(_ http: FakeHttpClient) -> FrigateCameraGroupsRepository {
        FrigateCameraGroupsRepository(config: .test, httpClient: http)
    }

    private func expect(status: Int, mapsTo error: CamerasError) async {
        let sut = makeSut(FakeHttpClient(.response(status: status, body: Data())))
        await #expect(throws: error) { try await sut.groups() }
    }
}
