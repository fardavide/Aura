import Testing

import CamerasEntities
import TestDoubles
@testable import SettingsDomain

struct SaveConnectionTests {

    @Test func `given valid settings when saving then the repository stores the trimmed connection`() throws {
        // given
        let repository = FakeSettingsRepository()
        let save = SaveConnection(repository: repository)

        // when
        try save.execute(settings(host: "  frigate.local  ", port: 5000))

        // then
        #expect(repository.savedConnection == settings(host: "frigate.local", port: 5000))
    }

    @Test func `given a local address when saving then both addresses are stored trimmed`() throws {
        // given
        let repository = FakeSettingsRepository()
        let save = SaveConnection(repository: repository)

        // when
        try save.execute(
            settings(host: "frigate.ts.net", port: 5000, local: address(host: " 192.168.1.50 ", port: 8_971))
        )

        // then
        #expect(repository.savedConnection?.local == address(host: "192.168.1.50", port: 8_971))
    }

    @Test func `given an empty host when saving then it throws invalidHost for the remote address`() {
        // given
        let save = SaveConnection(repository: FakeSettingsRepository())

        // when - then
        #expect(throws: SettingsError.invalidHost(.remote)) {
            try save.execute(settings(host: "   ", port: 5000))
        }
    }

    @Test func `given a port out of range when saving then it throws invalidPort for the remote address`() {
        // given
        let save = SaveConnection(repository: FakeSettingsRepository())

        // when - then
        #expect(throws: SettingsError.invalidPort(.remote)) {
            try save.execute(settings(host: "frigate.local", port: 70_000))
        }
    }

    @Test func `given an unusable local address when saving then it throws naming the local address`() {
        // given
        let repository = FakeSettingsRepository()
        let save = SaveConnection(repository: repository)

        // when - then
        #expect(throws: SettingsError.invalidPort(.local)) {
            try save.execute(
                settings(host: "frigate.ts.net", port: 5000, local: address(host: "192.168.1.50", port: 0))
            )
        }
        #expect(repository.savedConnection == nil)
    }
}

struct LoadConnectionTests {

    @Test func `given a stored connection when loading then it is returned`() {
        // given
        let repository = FakeSettingsRepository()
        repository.savedConnection = settings(host: "frigate.local", port: 5000)

        // when
        let loaded = LoadConnection(repository: repository).execute()

        // then
        #expect(loaded == settings(host: "frigate.local", port: 5000))
    }

    @Test func `given nothing stored when loading then it is nil`() {
        #expect(LoadConnection(repository: FakeSettingsRepository()).execute() == nil)
    }
}

struct ThemeUseCaseTests {

    @Test func `when saving a theme then the repository stores it`() {
        // given
        let repository = FakeSettingsRepository()

        // when
        SaveTheme(repository: repository).execute(.dark)

        // then
        #expect(repository.savedTheme == .dark)
    }

    @Test func `given a stored theme when loading then it is returned`() {
        // given
        let repository = FakeSettingsRepository()
        repository.savedTheme = .light

        // then
        #expect(LoadTheme(repository: repository).execute() == .light)
    }
}

struct CameraOrderUseCaseTests {

    @Test func `when saving an order then the repository stores it`() {
        // given
        let repository = FakeSettingsRepository()

        // when
        SaveCameraOrder(repository: repository).execute([CameraName("yard"), CameraName("door")])

        // then
        #expect(repository.savedCameraOrder == [CameraName("yard"), CameraName("door")])
    }

    @Test func `given a stored order when loading then it is returned`() {
        // given
        let repository = FakeSettingsRepository()
        repository.savedCameraOrder = [CameraName("garage")]

        // when - then
        #expect(LoadCameraOrder(repository: repository).execute() == [CameraName("garage")])
    }

    @Test func `when observing then the current order is emitted first and changes follow`() async {
        // given
        let repository = FakeSettingsRepository()
        repository.savedCameraOrder = [CameraName("yard")]
        var iterator = ObserveCameraOrder(repository: repository).execute().makeAsyncIterator()

        // when - then
        #expect(await iterator.next() == [CameraName("yard")])

        // when
        repository.saveCameraOrder([CameraName("door")])

        // then
        #expect(await iterator.next() == [CameraName("door")])
    }
}

struct DynamicCameraOrderUseCaseTests {

    @Test func `when turning the dynamic order off then the repository stores it`() {
        // given
        let repository = FakeSettingsRepository()

        // when
        SaveDynamicCameraOrder(repository: repository).execute(false)

        // then
        #expect(repository.savedDynamicCameraOrder == false)
    }

    @Test func `given the dynamic order is off when loading then it is returned`() {
        // given
        let repository = FakeSettingsRepository()
        repository.savedDynamicCameraOrder = false

        // when - then
        #expect(LoadDynamicCameraOrder(repository: repository).execute() == false)
    }

    @Test func `when observing then the current preference is emitted first and changes follow`() async {
        // given
        let repository = FakeSettingsRepository()
        var iterator = ObserveDynamicCameraOrder(repository: repository).execute().makeAsyncIterator()

        // when - then
        #expect(await iterator.next() == true)

        // when
        repository.saveDynamicCameraOrder(false)

        // then
        #expect(await iterator.next() == false)
    }
}

@MainActor
struct AppIconUseCaseTests {

    @Test func `given a chosen icon when loading then it is returned`() {
        // given
        let switcher = FakeAppIconSwitcher(current: .signal)

        // when - then
        #expect(LoadAppIcon(switcher: switcher).execute() == .signal)
    }

    @Test func `when changing the icon then the system applies it`() async throws {
        // given
        let switcher = FakeAppIconSwitcher()

        // when
        try await ChangeAppIcon(switcher: switcher).execute(.aurora)

        // then
        #expect(switcher.appliedIcons == [.aurora])
        #expect(switcher.current() == .aurora)
    }

    @Test func `given the system rejects the change when changing then it throws and the icon is unchanged`() async {
        // given
        let switcher = FakeAppIconSwitcher(current: .halo, applyResult: .failure(.iconChangeFailed))

        // when - then
        await #expect(throws: SettingsError.iconChangeFailed) {
            try await ChangeAppIcon(switcher: switcher).execute(.heavy)
        }
        #expect(switcher.current() == .halo)
    }
}

private func settings(host: String, port: Int, local: ServerAddress? = nil) -> ConnectionSettings {
    ConnectionSettings(remote: address(host: host, port: port), local: local, username: nil, password: nil)
}

private func address(host: String, port: Int) -> ServerAddress {
    ServerAddress(scheme: .http, host: host, port: port)
}
