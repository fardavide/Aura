import Foundation
import Testing

import CamerasDomain
import CommonFrigate
import CommonNetwork
import TestDoubles
@testable import CamerasData

struct FrigateRecordingStorageRepositoryTests {

    @Test func `given stats and config when observing storage then they are combined`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(routes: [
            ("api/stats", .response(status: 200, body: Data(statsJson.utf8))),
            ("api/config", .response(status: 200, body: Data(recordConfigJson.utf8))),
        ]))

        // when
        var stream = sut.observeStorage().makeAsyncIterator()

        // then
        let storage = try #require(await stream.next())
        #expect(storage?.freeBytes == Int64(1_464_844 * 1_048_576))
        #expect(storage?.retentionDays == 14)
    }

    @Test func `given credentials when observing storage then a basic auth header is sent`() async throws {
        // given
        let http = FakeHttpClient(routes: [
            ("api/stats", .response(status: 200, body: Data(statsJson.utf8))),
            ("api/config", .response(status: 200, body: Data(recordConfigJson.utf8))),
        ])
        let config = ServerConfig(
            scheme: .http, host: "frigate.test", port: 5000, username: "admin", password: "secret"
        )
        let sut = makeSut(http, config: config)

        // when
        var stream = sut.observeStorage().makeAsyncIterator()
        _ = await stream.next()

        // then
        #expect(http.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func `when observing storage then the request carries a bounded timeout`() async throws {
        // given
        let http = FakeHttpClient(routes: [
            ("api/stats", .response(status: 200, body: Data(statsJson.utf8))),
            ("api/config", .response(status: 200, body: Data(recordConfigJson.utf8))),
        ])
        let sut = makeSut(http)

        // when
        var stream = sut.observeStorage().makeAsyncIterator()
        _ = await stream.next()

        // then
        #expect(http.lastRequest?.timeoutInterval == 15)
    }

    @Test func `given a 401 when observing storage then the slot is emitted empty`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 401, body: Data())))

        // when
        var stream = sut.observeStorage().makeAsyncIterator()

        // then — resolves rather than hanging, so the grid isn't gated on a failed read
        #expect(await stream.next() == RecordingStorage?.none)
    }

    @Test func `given malformed json when observing storage then the slot is emitted empty`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 200, body: Data("not json".utf8))))

        // when
        var stream = sut.observeStorage().makeAsyncIterator()

        // then
        #expect(await stream.next() == RecordingStorage?.none)
    }

    @Test func `given a transport failure when observing storage then the slot is emitted empty`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(.failure(URLError(.notConnectedToInternet))))

        // when
        var stream = sut.observeStorage().makeAsyncIterator()

        // then
        #expect(await stream.next() == RecordingStorage?.none)
    }

    private func makeSut(
        _ http: FakeHttpClient,
        config: ServerConfig = .test
    ) -> FrigateRecordingStorageRepository {
        FrigateRecordingStorageRepository(
            config: config,
            httpClient: http,
            configProvider: FrigateConfigProvider(
                config: config, httpClient: http, refreshInterval: .seconds(120)
            )
        )
    }
}
