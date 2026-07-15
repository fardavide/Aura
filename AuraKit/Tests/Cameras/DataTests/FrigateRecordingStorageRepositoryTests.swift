import Foundation
import Testing

import CamerasDomain
import CommonFrigate
import CommonNetwork
import TestDoubles
@testable import CamerasData

struct FrigateRecordingStorageRepositoryTests {

    @Test func `given stats and config when fetching storage then they are combined`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(routes: [
            ("api/stats", .response(status: 200, body: Data(statsJson.utf8))),
            ("api/config", .response(status: 200, body: Data(recordConfigJson.utf8))),
        ]))

        // when
        let storage = try await sut.storage()

        // then
        #expect(storage.freeBytes == Int64(1_464_844 * 1_048_576))
        #expect(storage.retentionDays == 14)
    }

    @Test func `given credentials when fetching storage then a basic auth header is sent`() async throws {
        // given
        let http = FakeHttpClient(routes: [
            ("api/stats", .response(status: 200, body: Data(statsJson.utf8))),
            ("api/config", .response(status: 200, body: Data(recordConfigJson.utf8))),
        ])
        let config = ServerConfig(
            scheme: .http, host: "frigate.test", port: 5000, username: "admin", password: "secret"
        )
        let sut = FrigateRecordingStorageRepository(config: config, httpClient: http)

        // when
        _ = try await sut.storage()

        // then
        #expect(http.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func `given a 401 when fetching storage then it throws not authorized`() async {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 401, body: Data())))

        // when - then
        await #expect(throws: CamerasError.notAuthorized) { try await sut.storage() }
    }

    @Test func `given malformed json when fetching storage then it throws invalid data`() async {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 200, body: Data("not json".utf8))))

        // when - then
        await #expect(throws: CamerasError.invalidData) { try await sut.storage() }
    }

    @Test func `given a transport failure when fetching storage then it throws unreachable`() async {
        // given
        let sut = makeSut(FakeHttpClient(.failure(URLError(.notConnectedToInternet))))

        // when - then
        await #expect(throws: CamerasError.unreachable) { try await sut.storage() }
    }

    private func makeSut(_ http: FakeHttpClient) -> FrigateRecordingStorageRepository {
        FrigateRecordingStorageRepository(config: .test, httpClient: http)
    }
}
