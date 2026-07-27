import Foundation
import Testing

import CamerasDomain
import CommonFrigate
import CommonNetwork
import TestDoubles
@testable import CamerasData

struct FrigateCameraGroupsRepositoryTests {

    @Test func `given a 200 response when observing groups then they are decoded`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 200, body: Data(groupsConfigJson.utf8))))

        // when
        var stream = sut.observeGroups().makeAsyncIterator()

        // then
        #expect(Set(try #require(await stream.next()).map(\.name)) == ["Outdoor", "Indoor", "Overview"])
    }

    @Test func `given credentials when observing groups then a basic auth header is sent`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data(groupsConfigJson.utf8)))
        let config = ServerConfig(
            scheme: .http, host: "frigate.test", port: 5000, username: "admin", password: "secret"
        )
        let sut = FrigateCameraGroupsRepository(configProvider: makeProvider(config: config, http: http))

        // when
        var stream = sut.observeGroups().makeAsyncIterator()
        _ = await stream.next()

        // then
        #expect(http.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func `when observing groups then the request carries a bounded timeout`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data(groupsConfigJson.utf8)))
        let sut = makeSut(http)

        // when
        var stream = sut.observeGroups().makeAsyncIterator()
        _ = await stream.next()

        // then
        #expect(http.lastRequest?.timeoutInterval == 15)
    }

    @Test func `given malformed json when observing groups then no chips are emitted`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 200, body: Data("not json".utf8))))

        // when
        var stream = sut.observeGroups().makeAsyncIterator()

        // then — resolves rather than hanging, so the screen isn't gated on a broken read
        #expect(await stream.next() == [])
    }

    @Test func `given a transport failure when observing groups then no chips are emitted`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(.failure(URLError(.notConnectedToInternet))))

        // when
        var stream = sut.observeGroups().makeAsyncIterator()

        // then
        #expect(await stream.next() == [])
    }

    @Test func `given a later failure when observing groups then it is skipped, not emitted as empty`() async throws {
        // given
        let provider = makeProvider(http: FakeHttpClient(sequence: [
            .response(status: 200, body: Data(groupsConfigJson.utf8)),
            .response(status: 500, body: Data()),
            .response(status: 200, body: Data(singleGroupConfigJson.utf8)),
        ]))
        let sut = FrigateCameraGroupsRepository(configProvider: provider)
        var stream = sut.observeGroups().makeAsyncIterator()
        _ = await stream.next()

        // when
        await provider.refresh()
        await provider.refresh()

        // then — the failed round emitted nothing, so the next value is the third read's groups
        #expect(await stream.next()?.map(\.name) == ["Garden"])
    }

    private func makeSut(_ http: FakeHttpClient) -> FrigateCameraGroupsRepository {
        FrigateCameraGroupsRepository(configProvider: makeProvider(http: http))
    }

    private func makeProvider(
        config: ServerConfig = .test,
        http: FakeHttpClient
    ) -> FrigateConfigProvider {
        FrigateConfigProvider(config: config, httpClient: http, refreshInterval: .seconds(120))
    }
}
