import SwiftUI

import CamerasPresentation
import SettingsDomain
import SettingsPresentation

/// Routes between the camera grid (when a connection is configured) and Settings, and applies
/// the chosen theme. Reloads its config whenever Settings reports a save.
struct RootView: View {
    let composition: AppComposition

    @State private var connection: ConnectionSettings?
    @State private var theme: ThemePreference = .system
    @State private var showingSettings = false

    var body: some View {
        Group {
            if let connection {
                CameraGridView(
                    viewModel: composition.cameraGridViewModel(for: connection),
                    onOpenSettings: { showingSettings = true },
                    makeDetailViewModel: { composition.cameraDetailViewModel(for: $0, connection: connection) }
                )
                .id(identity(of: connection))
            } else {
                SettingsView(viewModel: composition.settingsViewModel(), onDone: reload)
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: composition.settingsViewModel()) {
                showingSettings = false
                reload()
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        connection = composition.currentConnection()
        theme = composition.currentTheme()
    }

    /// Rebuilds the grid (and its view model) when the connection changes.
    private func identity(of connection: ConnectionSettings) -> String {
        "\(connection.scheme.rawValue)://\(connection.host):\(connection.port)"
    }
}

private extension ThemePreference {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
