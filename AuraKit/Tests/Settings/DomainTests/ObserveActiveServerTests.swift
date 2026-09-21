import Testing

import TestDoubles
@testable import SettingsDomain

struct ObserveActiveServerTests {

    @Test func `given no local address when observing then the remote server is used without probing`() async {
        // given
        let scenario = Scenario(isLocalReachable: true)
        var iterator = scenario.sut.execute(for: connection(local: nil)).makeAsyncIterator()

        // when
        let resolved = await iterator.next()

        // then
        #expect(resolved == remoteServer)
        #expect(scenario.probe.probedServers.isEmpty)
    }

    @Test func `given no Wi-Fi when observing then the remote server is used without probing`() async {
        // given — cellular: a private address cannot work, so the probe would only burn the timeout
        let scenario = Scenario(hasLocalNetwork: false, isLocalReachable: true)
        var iterator = scenario.sut.execute(for: connection()).makeAsyncIterator()

        // when
        let resolved = await iterator.next()

        // then
        #expect(resolved == remoteServer)
        #expect(scenario.probe.probedServers.isEmpty)
    }

    @Test func `given the local address answers on Wi-Fi when observing then the local server is used`() async {
        // given
        let scenario = Scenario(isLocalReachable: true)
        var iterator = scenario.sut.execute(for: connection()).makeAsyncIterator()

        // when
        let resolved = await iterator.next()

        // then
        #expect(resolved == localServer)
        #expect(scenario.probe.probedServers == [localServer])
        #expect(scenario.probe.probedTimeouts == [.milliseconds(250)])
    }

    @Test func `given the local address is silent on Wi-Fi when observing then the remote server is used`() async {
        // given — a foreign Wi-Fi, where the home address resolves to nothing
        let scenario = Scenario(isLocalReachable: false)
        var iterator = scenario.sut.execute(for: connection()).makeAsyncIterator()

        // when
        let resolved = await iterator.next()

        // then
        #expect(resolved == remoteServer)
    }

    @Test func `given the device leaves the home network when observing then it switches to the remote server`() async {
        // given
        let scenario = Scenario(isLocalReachable: true)
        var iterator = scenario.sut.execute(for: connection()).makeAsyncIterator()
        #expect(await iterator.next() == localServer)

        // when — Wi-Fi drops on the way out of the house
        scenario.networkPaths.send(false)

        // then
        #expect(await iterator.next() == remoteServer)
    }

    @Test func `given the device comes home when observing then it switches to the local server`() async {
        // given
        let scenario = Scenario(hasLocalNetwork: false, isLocalReachable: true)
        var iterator = scenario.sut.execute(for: connection()).makeAsyncIterator()
        #expect(await iterator.next() == remoteServer)

        // when
        scenario.networkPaths.send(true)

        // then
        #expect(await iterator.next() == localServer)
    }

    @Test func `given the route is unchanged when the network flaps then nothing is re-emitted`() async {
        // given — joining a café's Wi-Fi resolves to remote, exactly like the cellular it replaced
        let scenario = Scenario(hasLocalNetwork: false, isLocalReachable: false)
        var iterator = scenario.sut.execute(for: connection()).makeAsyncIterator()
        #expect(await iterator.next() == remoteServer)

        // when
        scenario.networkPaths.send(true)
        scenario.networkPaths.send(false)
        scenario.networkPaths.send(true)
        scenario.networkPaths.finish()

        // then — the stream ends without ever repeating itself, so the app is never rebuilt for
        // a change that isn't one
        #expect(await iterator.next() == nil)
    }
}

private let remoteAddress = ServerAddress(scheme: .https, host: "frigate.ts.net", port: 8_971)
private let localAddress = ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000)

private let remoteServer = ActiveServer(
    route: .remote, address: remoteAddress, username: "admin", password: "hunter2"
)
private let localServer = ActiveServer(
    route: .local, address: localAddress, username: "admin", password: "hunter2"
)

private func connection(local: ServerAddress? = localAddress) -> ConnectionSettings {
    ConnectionSettings(remote: remoteAddress, local: local, username: "admin", password: "hunter2")
}

private struct Scenario {
    let probe: FakeServerReachabilityProbe
    let networkPaths: FakeNetworkPathObserver
    let sut: ObserveActiveServer

    init(hasLocalNetwork: Bool = true, isLocalReachable: Bool) {
        probe = FakeServerReachabilityProbe(isReachable: isLocalReachable)
        networkPaths = FakeNetworkPathObserver(isLocalNetworkAvailable: hasLocalNetwork)
        sut = ObserveActiveServer(
            probe: probe,
            networkPaths: networkPaths,
            localProbeTimeout: .milliseconds(250)
        )
    }
}
