import SwiftUI
import Testing

import SettingsDomain
import SettingsPresentation
import TestDoubles

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
        assertScreenSnapshot(SettingsView(viewModel: viewModel, makeCameraOrderViewModel: nil, onDone: {}), named: "first-run")
    }

    // The password SecureField renders BLANK in the reference on purpose: iOS excludes
    // isSecureTextEntry content from window-hierarchy captures (the drawHierarchyInKeyWindow
    // path this suite needs for Liquid Glass). Verified against a plain layer-rendering probe,
    // which shows the seven bullets.
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
        assertScreenSnapshot(SettingsView(viewModel: viewModel, makeCameraOrderViewModel: nil, onDone: {}), named: "saved")
    }

    @Test func `given an empty host when saving then the error is shown`() {
        // given
        let viewModel = settingsViewModel(connection: nil, theme: .system)
        viewModel.onAppear()

        // when
        viewModel.save()

        // then
        assertScreenSnapshot(SettingsView(viewModel: viewModel, makeCameraOrderViewModel: nil, onDone: {}), named: "invalid-host")
    }
}

// MARK: - View-model builder

/// A view model over a fake repository holding the given saved state — the same four-use-case
/// wiring the composition root does over the real UserDefaults + Keychain repository.
@MainActor
private func settingsViewModel(connection: ConnectionSettings?, theme: ThemePreference) -> SettingsViewModel {
    let repository = FakeSettingsRepository(connection: connection, theme: theme)
    return SettingsViewModel(
        loadConnection: LoadConnection(repository: repository),
        saveConnection: SaveConnection(repository: repository),
        loadTheme: LoadTheme(repository: repository),
        saveTheme: SaveTheme(repository: repository)
    )
}
