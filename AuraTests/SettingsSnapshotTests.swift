import SwiftUI
import Testing

import SettingsDomain
import SettingsPresentation

/// Screenshot tests for the Settings screen across its states, captured on every device +
/// orientation (iOS). The screen is fully synchronous (no network, no dates): the fake
/// repository's return values drive the fields, and the view model is pre-driven so the view's
/// own `onAppear` re-load settles on the same pixels.
@MainActor
struct SettingsSnapshotTests {

    @Test func `given no saved connection when shown then it matches the reference`() {
        // given
        let viewModel = settingsViewModel(connection: nil, theme: .system)
        viewModel.onAppear()

        // then
        assertScreenSnapshot(SettingsView(viewModel: viewModel, onDone: {}), named: "first-run")
    }

    @Test func `given a saved connection when shown then it matches the reference`() {
        // given
        let viewModel = settingsViewModel(
            connection: ConnectionSettings(
                scheme: .https, host: "frigate.local", port: 8_971,
                username: "admin", password: "hunter2"
            ),
            theme: .dark
        )
        viewModel.onAppear()

        // then
        assertScreenSnapshot(SettingsView(viewModel: viewModel, onDone: {}), named: "saved")
    }

    @Test func `given an empty host when saving then the error is shown`() {
        // given
        let viewModel = settingsViewModel(connection: nil, theme: .system)
        viewModel.onAppear()

        // when
        viewModel.save()

        // then
        assertScreenSnapshot(SettingsView(viewModel: viewModel, onDone: {}), named: "invalid-host")
    }
}

// MARK: - View-model builder

/// A view model over a fake repository holding the given saved state — the same four-use-case
/// wiring the composition root does over the real UserDefaults + Keychain repository.
@MainActor
private func settingsViewModel(connection: ConnectionSettings?, theme: ThemePreference) -> SettingsViewModel {
    let repository = FakeSettings(connection: connection, theme: theme)
    return SettingsViewModel(
        loadConnection: LoadConnection(repository: repository),
        saveConnection: SaveConnection(repository: repository),
        loadTheme: LoadTheme(repository: repository),
        saveTheme: SaveTheme(repository: repository)
    )
}

// MARK: - Fakes

private struct FakeSettings: SettingsRepository {
    let connection: ConnectionSettings?
    let theme: ThemePreference
    func loadConnection() -> ConnectionSettings? { connection }
    func saveConnection(_ settings: ConnectionSettings) {}
    func loadTheme() -> ThemePreference { theme }
    func saveTheme(_ theme: ThemePreference) {}
}
