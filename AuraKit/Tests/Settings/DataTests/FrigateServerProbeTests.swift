import Foundation
import Testing

import SettingsDomain
import TestDoubles
@testable import SettingsData

struct FrigateServerProbeTests {

    @Test func `when probing then it asks the version endpoint on the given address`() async {
        // given
        let scenario = Scenario(.response(status: 200, body: version))

        // when
        _ = await scenario.sut.canReach(server, within: .seconds(1))

        // then
        #expect(scenario.http.lastRequest?.url?.absoluteString == "http://192.168.1.50:5000/api/version")
    }

    @Test func `given credentials when probing then the request carries basic auth`() async {
        // given — a server behind auth answers 401 without it, which would read as unreachable
        let scenario = Scenario(.response(status: 200, body: version))

        // when
        _ = await scenario.sut.canReach(server, within: .seconds(1))

        // then
        #expect(
            scenario.http.lastRequest?.value(forHTTPHeaderField: "Authorization")
                == "Basic \(Data("admin:hunter2".utf8).base64EncodedString())"
        )
    }

    @Test func `when probing then the request is bounded by the given timeout`() async {
        // given
        let scenario = Scenario(.response(status: 200, body: version))

        // when
        _ = await scenario.sut.canReach(server, within: .milliseconds(600))

        // then
        #expect(scenario.http.lastRequest?.timeoutInterval == 0.6)
    }

    @Test func `given the server answers with its version when probing then it is reachable`() async {
        // given
        let scenario = Scenario(.response(status: 200, body: version))

        // when - then
        #expect(await scenario.sut.canReach(server, within: .seconds(1)))
    }

    @Test func `given the address is refused when probing then it is not reachable`() async {
        // given
        let scenario = Scenario(.failure(URLError(.cannotConnectToHost)))

        // when - then
        #expect(await scenario.sut.canReach(server, within: .seconds(1)) == false)
    }

    @Test func `given the address rejects the credentials when probing then it is not reachable`() async {
        // given — reachable but unusable is the same answer: fall back to the other address
        let scenario = Scenario(.response(status: 401, body: Data()))

        // when - then
        #expect(await scenario.sut.canReach(server, within: .seconds(1)) == false)
    }

    @Test func `given some other server answers at the address when probing then it is not reachable`() async {
        // given — a café router's own web UI on the same private IP; switching the app onto it
        // would be worse than falling back to remote
        let scenario = Scenario(.response(status: 200, body: Data("<!DOCTYPE html><html>".utf8)))

        // when - then
        #expect(await scenario.sut.canReach(server, within: .seconds(1)) == false)
    }

    @Test func `given the address never answers when probing then it gives up within the timeout`() async {
        // given — packets dropped in silence, so nothing ever fails; only the deadline ends it
        let scenario = Scenario(.stall)
        let started = ContinuousClock.now

        // when
        let isReachable = await scenario.sut.canReach(server, within: .milliseconds(200))

        // then
        #expect(isReachable == false)
        #expect(ContinuousClock.now - started < .seconds(2))
    }
}

private let version = Data("0.17.2\n".utf8)

private let server = ActiveServer(
    route: .local,
    address: ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000),
    username: "admin",
    password: "hunter2"
)

private struct Scenario {
    let http: FakeHttpClient
    let sut: FrigateServerProbe

    init(_ outcome: FakeHttpClient.Outcome) {
        http = FakeHttpClient(outcome)
        sut = FrigateServerProbe(httpClient: http)
    }
}
