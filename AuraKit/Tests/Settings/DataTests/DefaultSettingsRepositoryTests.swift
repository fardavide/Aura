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
        scenario.sut.saveConnection(
            ConnectionSettings(scheme: .https, host: "frigate.local", port: 8971, username: "admin", password: "secret")
        )

        // when
        let loaded = scenario.sut.loadConnection()

        // then
        #expect(loaded == ConnectionSettings(
            scheme: .https, host: "frigate.local", port: 8971, username: "admin", password: "secret"
        ))
    }

    @Test func `given a password when saving then it is kept in the keychain not user defaults`() {
        // given
        let scenario = Scenario()
        scenario.sut.saveConnection(
            ConnectionSettings(scheme: .http, host: "h", port: 5000, username: nil, password: "secret")
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

    @Test func `given a saved theme when loading then it round-trips`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.saveTheme(.dark)

        // then
        #expect(scenario.sut.loadTheme() == .dark)
    }
}

private struct Scenario {
    let defaults: UserDefaults
    let sut: DefaultSettingsRepository

    init() {
        defaults = UserDefaults(suiteName: "SettingsDataTests-\(UUID().uuidString)")!
        sut = DefaultSettingsRepository(defaults: defaults, keychain: FakeKeychainStore())
    }
}
