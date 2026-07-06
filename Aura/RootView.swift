import SwiftUI

import CamerasDomain
import CamerasPresentation
import EventsDomain
import EventsPresentation
import SettingsDomain
import SettingsPresentation
import TimelinePresentation

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
                TabView {
                    CameraGridView(
                        viewModel: composition.cameraGridViewModel(for: connection),
                        onOpenSettings: { showingSettings = true },
                        makeDetailViewModel: { composition.cameraDetailViewModel(for: $0, connection: connection) }
                    )
                    .tabItem { Label("Cameras", systemImage: "video") }

                    TimelineScreenView(
                        viewModel: composition.timelineScreenViewModel(for: connection),
                        makeTileViewModel: { composition.previewTileViewModel(for: $0, connection: connection) },
                        onOpenRecording: { _, _ in }
                    )
                    .tabItem { Label("Timeline", systemImage: "calendar.day.timeline.left") }

                    EventsListView(
                        viewModel: composition.eventsListViewModel(for: connection),
                        onOpenSettings: { showingSettings = true },
                        makeDetailViewModel: { composition.eventDetailViewModel(for: $0, connection: connection) }
                    )
                    .tabItem { Label("Events", systemImage: "bell") }
                }
                .id(identity(of: connection))
            } else {
                SettingsView(
                    viewModel: composition.settingsViewModel(),
                    makeServerSettingsViewModel: { composition.serverSettingsViewModel() },
                    makeCameraOrderViewModel: nil,
                    onDone: reload
                )
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                viewModel: composition.settingsViewModel(),
                makeServerSettingsViewModel: { composition.serverSettingsViewModel() },
                makeCameraOrderViewModel: connection.map { connection in
                    { composition.cameraOrderViewModel(for: connection) }
                }
            ) {
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
