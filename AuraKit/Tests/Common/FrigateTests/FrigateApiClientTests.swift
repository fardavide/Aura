import Foundation
import Testing

import CommonFrigate
import CommonNetwork
import TestDoubles

struct FrigateApiClientTests {

    @Test func `given a 200 response when getting then it returns the body`() async throws {
        // given
        let body = Data("ok".utf8)
        let sut = FrigateApiClient(
            config: .test, httpClient: FakeHttpClient(.response(status: 200, body: body))
        )

        // when - then
        #expect(try await sut.get(url) == body)
    }

    @Test func `given credentials when getting then a basic auth header is sent`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data()))
        let config = ServerConfig(
            scheme: .http, host: "frigate.test", port: 5000, username: "admin", password: "secret"
        )
        let sut = FrigateApiClient(config: config, httpClient: http)

        // when
        _ = try await sut.get(url)

        // then
        #expect(http.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func `given no credentials when getting then no auth header is sent`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data()))
        let sut = FrigateApiClient(config: .test, httpClient: http)

        // when
        _ = try await sut.get(url)

        // then
        #expect(http.lastRequest?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func `when getting then the request carries a bounded timeout`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data()))
        let sut = FrigateApiClient(config: .test, httpClient: http)

        // when
        _ = try await sut.get(url)

        // then
        #expect(http.lastRequest?.timeoutInterval == 15)
    }

    @Test func `given a 401 when getting then it throws not authorized`() async {
        await expect(status: 401, mapsTo: .notAuthorized)
    }

    @Test func `given a 403 when getting then it throws not authorized`() async {
        await expect(status: 403, mapsTo: .notAuthorized)
    }

    @Test func `given a 503 when getting then it throws server unavailable`() async {
        await expect(status: 503, mapsTo: .serverUnavailable)
    }

    @Test func `given a 404 when getting then it throws unknown`() async {
        await expect(status: 404, mapsTo: .unknown)
    }

    @Test func `given a transport failure when getting then it throws unreachable`() async {
        // given
        let sut = FrigateApiClient(
            config: .test, httpClient: FakeHttpClient(.failure(URLError(.notConnectedToInternet)))
        )

        // when - then
        await #expect(throws: FrigateApiError.unreachable) { try await sut.get(url) }
    }

    private func expect(status: Int, mapsTo error: FrigateApiError) async {
        let sut = FrigateApiClient(
            config: .test, httpClient: FakeHttpClient(.response(status: status, body: Data()))
        )
        await #expect(throws: error) { try await sut.get(url) }
    }
}

private let url = URL(string: "http://frigate.test:5000/api/config")!

extension ServerConfig {
    static let test = ServerConfig(
        scheme: .http, host: "frigate.test", port: 5000, username: nil, password: nil
    )
}
