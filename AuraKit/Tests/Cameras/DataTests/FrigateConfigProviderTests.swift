import Foundation
import Testing

import CommonFrigate
import CommonNetwork
import TestDoubles

@testable import CamerasData

struct FrigateConfigProviderTests {

    @Test func `given two reads when getting the config then the server is asked once`() async throws {
        // given
        let scenario = Scenario(body: configBody)

        // when
        _ = try await scenario.sut.config()
        _ = try await scenario.sut.config()

        // then
        #expect(scenario.http.requestCount == 1)
    }

    @Test func `given an unauthorized server when getting the config then it throws not authorized`() async {
        // given
        let scenario = Scenario(status: 401)

        // when - then
        await #expect(throws: FrigateApiError.notAuthorized) { try await scenario.sut.config() }
    }

    @Test func `given a failed fetch when reading again then it retries instead of caching the failure`() async {
        // given
        let scenario = Scenario(status: 500)
        _ = try? await scenario.sut.config()

        // when
        _ = try? await scenario.sut.config()

        // then
        #expect(scenario.http.requestCount == 2)
    }

    @Test func `given concurrent reads when getting the config then they share one fetch`() async throws {
        // given
        let scenario = Scenario(body: configBody)

        // when
        async let first = scenario.sut.config()
        async let second = scenario.sut.config()
        _ = try await (first, second)

        // then
        #expect(scenario.http.requestCount == 1)
    }

    @Test func `given a loaded config when reloading then the server is read again`() async throws {
        // given
        let scenario = Scenario(body: configBody)
        _ = try await scenario.sut.config()

        // when
        _ = try await scenario.sut.reloadConfig()

        // then
        #expect(scenario.http.requestCount == 2)
    }

    @Test func `when reloading then observers receive the re-read config`() async throws {
        // given
        let scenario = Scenario(sequence: [
            .response(status: 200, body: configBody),
            .response(status: 200, body: changedConfigBody),
        ])
        var stream = await scenario.sut.observeConfig().makeAsyncIterator()
        _ = await stream.next()

        // when
        _ = try await scenario.sut.reloadConfig()

        // then
        #expect(try await stream.next()?.get() == changedConfigBody)
    }

    // MARK: - Observing

    @Test func `given a loaded config when observing then the current config arrives first`() async throws {
        // given
        let scenario = Scenario(body: configBody)
        _ = try await scenario.sut.config()

        // when
        var stream = await scenario.sut.observeConfig().makeAsyncIterator()

        // then
        #expect(try await stream.next()?.get() == configBody)
    }

    @Test func `given nothing loaded yet when observing then it fetches and emits the config`() async throws {
        // given
        let scenario = Scenario(body: configBody)

        // when
        var stream = await scenario.sut.observeConfig().makeAsyncIterator()

        // then
        #expect(try await stream.next()?.get() == configBody)
    }

    @Test func `when refreshing then observers receive the new config`() async throws {
        // given
        let scenario = Scenario(sequence: [
            .response(status: 200, body: configBody),
            .response(status: 200, body: changedConfigBody),
        ])
        _ = try await scenario.sut.config()
        var stream = await scenario.sut.observeConfig().makeAsyncIterator()
        _ = await stream.next()

        // when
        await scenario.sut.refresh()

        // then
        #expect(try await stream.next()?.get() == changedConfigBody)
    }

    @Test(.timeLimit(.minutes(1)))
    func `given an observer when the refresh interval elapses then the config is re-read`() async throws {
        // given
        let scenario = Scenario(
            sequence: [
                .response(status: 200, body: configBody),
                .response(status: 200, body: changedConfigBody),
            ],
            refreshInterval: .milliseconds(10)
        )
        var stream = await scenario.sut.observeConfig().makeAsyncIterator()
        #expect(try await stream.next()?.get() == configBody)

        // when - then
        #expect(try await stream.next()?.get() == changedConfigBody)
    }

    @Test func `given an unreachable server when observing then the failure is emitted`() async throws {
        // given
        let scenario = Scenario(status: 503)

        // when
        var stream = await scenario.sut.observeConfig().makeAsyncIterator()

        // then — a subscriber gating its first paint on this must not wait forever
        #expect(await stream.next() == .failure(.serverUnavailable))
    }

    @Test func `given a failed refresh when observing then the last good config is kept`() async throws {
        // given
        let scenario = Scenario(sequence: [
            .response(status: 200, body: configBody),
            .response(status: 500, body: Data()),
        ])
        _ = try await scenario.sut.config()

        // when
        await scenario.sut.refresh()

        // then
        var stream = await scenario.sut.observeConfig().makeAsyncIterator()
        #expect(try await stream.next()?.get() == configBody)
    }
}

private let configBody = Data(#"{"cameras":{"driveway":{}}}"#.utf8)
private let changedConfigBody = Data(#"{"cameras":{"driveway":{},"porch":{}}}"#.utf8)

private struct Scenario {
    let http: FakeHttpClient
    let sut: FrigateConfigProvider

    init(body: Data = configBody, status: Int = 200) {
        self.init(http: FakeHttpClient(.response(status: status, body: body)))
    }

    init(sequence: [FakeHttpClient.Outcome], refreshInterval: Duration = .seconds(120)) {
        self.init(http: FakeHttpClient(sequence: sequence), refreshInterval: refreshInterval)
    }

    private init(http: FakeHttpClient, refreshInterval: Duration = .seconds(120)) {
        self.http = http
        sut = FrigateConfigProvider(
            config: ServerConfig(
                scheme: .http, host: "frigate.test", port: 5000, username: nil, password: nil
            ),
            httpClient: http,
            refreshInterval: refreshInterval
        )
    }
}
