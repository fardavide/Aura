import Testing

import SettingsDomain
import TestDoubles
@testable import SettingsPresentation

@MainActor
struct SettingsViewModelTests {

    @Test func `given a saved connection when appearing then the fields are prefilled`() {
        // given
        let repository = FakeSettingsRepository()
        repository.savedConnection = ConnectionSettings(
            scheme: .https, host: "frigate.local", port: 8971, username: "admin", password: "pw"
        )
        let sut = makeViewModel(repository)

        // when
        sut.onAppear()

        // then
        #expect(sut.scheme == .https)
        #expect(sut.host == "frigate.local")
        #expect(sut.port == "8971")
        #expect(sut.username == "admin")
        #expect(sut.password == "pw")
    }

    @Test func `given valid fields when saving then the connection is persisted`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.host = "frigate.local"
        sut.port = "5000"

        // when
        sut.save()

        // then
        #expect(repository.savedConnection == ConnectionSettings(
            scheme: .http, host: "frigate.local", port: 5000, username: nil, password: nil
        ))
        #expect(sut.didSave)
        #expect(sut.errorMessage == nil)
    }

    @Test func `given an empty host when saving then it errors and does not persist`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.host = "   "

        // when
        sut.save()

        // then
        #expect(sut.errorMessage != nil)
        #expect(repository.savedConnection == nil)
        #expect(sut.didSave == false)
    }

    @Test func `given a non-numeric port when saving then it errors`() {
        // given
        let sut = makeViewModel()
        sut.host = "frigate.local"
        sut.port = "abc"

        // when
        sut.save()

        // then
        #expect(sut.errorMessage != nil)
    }

    @Test func `when saving then the theme is persisted`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)
        sut.host = "frigate.local"
        sut.theme = .dark

        // when
        sut.save()

        // then
        #expect(repository.savedTheme == .dark)
    }
}

@MainActor
private func makeViewModel(_ repository: FakeSettingsRepository = FakeSettingsRepository()) -> SettingsViewModel {
    SettingsViewModel(
        loadConnection: LoadConnection(repository: repository),
        saveConnection: SaveConnection(repository: repository),
        loadTheme: LoadTheme(repository: repository),
        saveTheme: SaveTheme(repository: repository)
    )
}
