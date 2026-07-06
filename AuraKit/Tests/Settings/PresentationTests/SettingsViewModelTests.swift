import Testing

import SettingsDomain
import TestDoubles
@testable import SettingsPresentation

@MainActor
struct SettingsViewModelTests {

    @Test func `given a saved theme when appearing then it is prefilled`() {
        // given
        let repository = FakeSettingsRepository()
        repository.savedTheme = .light
        let sut = makeViewModel(repository)

        // when
        sut.onAppear()

        // then
        #expect(sut.theme == .light)
    }

    @Test func `when the theme changes then it is saved immediately`() {
        // given
        let repository = FakeSettingsRepository()
        let sut = makeViewModel(repository)

        // when
        sut.theme = .dark

        // then
        #expect(repository.savedTheme == .dark)
    }
}

@MainActor
private func makeViewModel(_ repository: FakeSettingsRepository = FakeSettingsRepository()) -> SettingsViewModel {
    SettingsViewModel(
        loadTheme: LoadTheme(repository: repository),
        saveTheme: SaveTheme(repository: repository)
    )
}
