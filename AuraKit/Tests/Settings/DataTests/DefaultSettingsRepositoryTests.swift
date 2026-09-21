import Foundation
import Testing

import CamerasEntities
import CommonKeychain
import SettingsDomain
import TestDoubles
@testable import SettingsData

struct DefaultSettingsRepositoryTests {

    @Test func `given a saved connection when loading then it round-trips`() {
        // given
        let scenario = Scenario()
        scenario.sut.saveConnection(connection(
            local: ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000)
        ))

        // when
        let loaded = scenario.sut.loadConnection()

        // then
        #expect(loaded == connection(local: ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000)))
    }

    @Test func `given no local address when loading then only the remote one comes back`() {
        // given — also the shape of every install that predates the local address
        let scenario = Scenario()
        scenario.sut.saveConnection(connection(local: nil))

        // when - then
        #expect(scenario.sut.loadConnection()?.local == nil)
        #expect(scenario.sut.loadConnection()?.remote.host == "frigate.ts.net")
    }

    @Test func `given a saved local address when it is removed then it does not come back`() {
        // given
        let scenario = Scenario()
        scenario.sut.saveConnection(connection(
            local: ServerAddress(scheme: .http, host: "192.168.1.50", port: 5000)
        ))

        // when
        scenario.sut.saveConnection(connection(local: nil))

        // then
        #expect(scenario.sut.loadConnection()?.local == nil)
    }

    @Test func `given a password when saving then it is kept in the keychain not user defaults`() {
        // given
        let scenario = Scenario()
        scenario.sut.saveConnection(
            ConnectionSettings(
                remote: ServerAddress(scheme: .http, host: "h", port: 5000),
                local: nil,
                username: nil,
                password: "secret"
            )
        )

        // when — a repository over the same defaults but a fresh keychain
        let withoutKeychain = DefaultSettingsRepository(
            defaults: scenario.defaults, keychain: FakeKeychainStore()
        )

        // then — password came only from the keychain
        #expect(scenario.sut.loadConnection()?.password == "secret")
        #expect(withoutKeychain.loadConnection()?.password == nil)
    }

    @Test func `given nothing saved when loading the connection then it is nil`() {
        #expect(Scenario().sut.loadConnection() == nil)
    }

    @Test func `given no saved theme when loading then it defaults to system`() {
        #expect(Scenario().sut.loadTheme() == .system)
    }

    @Test func `given no saved camera order when loading then it is empty`() {
        #expect(Scenario().sut.loadCameraOrder() == [])
    }

    @Test func `given a saved camera order when loading then it round-trips`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.saveCameraOrder([CameraName("yard"), CameraName("front door")])

        // then
        #expect(scenario.sut.loadCameraOrder() == [CameraName("yard"), CameraName("front door")])
    }

    @Test func `given a saved camera order when observing then the current order is emitted first`() async {
        // given
        let scenario = Scenario()
        scenario.sut.saveCameraOrder([CameraName("yard")])

        // when
        var iterator = scenario.sut.observeCameraOrder().makeAsyncIterator()

        // then
        #expect(await iterator.next() == [CameraName("yard")])
    }

    @Test func `given an observer when a new order is saved then it is emitted`() async {
        // given
        let scenario = Scenario()
        var iterator = scenario.sut.observeCameraOrder().makeAsyncIterator()
        _ = await iterator.next()

        // when
        scenario.sut.saveCameraOrder([CameraName("front door")])

        // then
        #expect(await iterator.next() == [CameraName("front door")])
    }

    @Test func `given nothing saved when loading the dynamic camera order then it is on`() {
        #expect(Scenario().sut.loadDynamicCameraOrder() == true)
    }

    @Test func `given the dynamic camera order turned off when loading then it round-trips`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.saveDynamicCameraOrder(false)

        // then
        #expect(scenario.sut.loadDynamicCameraOrder() == false)
    }

    @Test func `given an observer when the dynamic camera order is turned off then it is emitted`() async {
        // given
        let scenario = Scenario()
        var iterator = scenario.sut.observeDynamicCameraOrder().makeAsyncIterator()
        _ = await iterator.next()

        // when
        scenario.sut.saveDynamicCameraOrder(false)

        // then
        #expect(await iterator.next() == false)
    }

    @Test func `given a saved theme when loading then it round-trips`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.saveTheme(.dark)

        // then
        #expect(scenario.sut.loadTheme() == .dark)
    }
}

private func connection(local: ServerAddress?) -> ConnectionSettings {
    ConnectionSettings(
        remote: ServerAddress(scheme: .https, host: "frigate.ts.net", port: 8_971),
        local: local,
        username: "admin",
        password: "secret"
    )
}

private struct Scenario {
    let defaults: UserDefaults
    let sut: DefaultSettingsRepository

    init() {
        defaults = UserDefaults(suiteName: "SettingsDataTests-\(UUID().uuidString)")!
        sut = DefaultSettingsRepository(defaults: defaults, keychain: FakeKeychainStore())
    }
}
