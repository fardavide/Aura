import Testing

import SettingsDomain
import TestDoubles
@testable import SettingsPresentation

@MainActor
struct SettingsViewModelTests {

    @Test func `given a saved theme when appearing then it is prefilled`() {
        // given
        let scenario = Scenario(theme: .light)

        // when
        scenario.sut.onAppear()

        // then
        #expect(scenario.sut.theme == .light)
    }

    @Test func `when the theme changes then it is saved immediately`() {
        // given
        let scenario = Scenario()

        // when
        scenario.sut.theme = .dark

        // then
        #expect(scenario.settings.savedTheme == .dark)
    }
}

@MainActor
private struct Scenario {
    let settings: FakeSettingsRepository
    let sut: SettingsViewModel

    init(theme: ThemePreference = .system) {
        settings = FakeSettingsRepository(theme: theme)
        sut = SettingsViewModel(
            loadTheme: LoadTheme(repository: settings),
            saveTheme: SaveTheme(repository: settings)
        )
    }
}
