import Foundation
import Testing

import CamerasDomain
import CommonFrigate
import CommonNetwork
import TestDoubles
@testable import CamerasData

struct FrigateTodayEventsRepositoryTests {

    @Test func `given a 200 response when fetching labels then each event's label is read`() async throws {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 200, body: Data(todayEventsJson.utf8))))

        // when
        let labels = try await sut.labels(since: since)

        // then
        #expect(labels == ["person", "car", "person"])
    }

    @Test func `when fetching labels then the request bounds the window with an after query`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data(todayEventsJson.utf8)))
        let sut = FrigateTodayEventsRepository(config: .test, httpClient: http)

        // when
        _ = try await sut.labels(since: since)

        // then
        let url = try #require(http.lastRequest?.url?.absoluteString)
        #expect(url.contains("after=1000000"))
    }

    @Test func `given a 401 when fetching labels then it throws not authorized`() async {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 401, body: Data())))

        // when - then
        await #expect(throws: CamerasError.notAuthorized) { try await sut.labels(since: since) }
    }

    @Test func `given malformed json when fetching labels then it throws invalid data`() async {
        // given
        let sut = makeSut(FakeHttpClient(.response(status: 200, body: Data("not json".utf8))))

        // when - then
        await #expect(throws: CamerasError.invalidData) { try await sut.labels(since: since) }
    }

    @Test func `given a transport failure when fetching labels then it throws unreachable`() async {
        // given
        let sut = makeSut(FakeHttpClient(.failure(URLError(.notConnectedToInternet))))

        // when - then
        await #expect(throws: CamerasError.unreachable) { try await sut.labels(since: since) }
    }

    private func makeSut(_ http: FakeHttpClient) -> FrigateTodayEventsRepository {
        FrigateTodayEventsRepository(config: .test, httpClient: http)
    }
}

private let since = Date(timeIntervalSince1970: 1_000_000)
