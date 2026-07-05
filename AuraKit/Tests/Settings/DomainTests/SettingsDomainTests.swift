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

    @Test func `given an empty host when saving then it throws invalidHost`() {
        // given
        let save = SaveConnection(repository: FakeSettingsRepository())

        // when - then
        #expect(throws: SettingsError.invalidHost) {
            try save.execute(settings(host: "   ", port: 5000))
        }
    }

    @Test func `given a port out of range when saving then it throws invalidPort`() {
        // given
        let save = SaveConnection(repository: FakeSettingsRepository())

        // when - then
        #expect(throws: SettingsError.invalidPort) {
            try save.execute(settings(host: "frigate.local", port: 70_000))
        }
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

private func settings(host: String, port: Int) -> ConnectionSettings {
    ConnectionSettings(scheme: .http, host: host, port: port, username: nil, password: nil)
}
