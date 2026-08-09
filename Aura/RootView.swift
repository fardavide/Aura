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
    @State private var selectedTab = AppTab.cameras
    // Bumped per tab on selection so only the newly selected icon bounces — keying the
    // effect on `selectedTab == tab` would also bounce the icon being deselected.
    @State private var iconBounces: [AppTab: Int] = [:]

    var body: some View {
        Group {
            if let connection {
                TabView(selection: $selectedTab) {
                    Tab(value: AppTab.cameras) {
                        CameraGridView(
                            viewModel: composition.cameraGridViewModel(for: connection),
                            onOpenSettings: { showingSettings = true },
                            makeDetailViewModel: { composition.cameraDetailViewModel(for: $0, connection: connection) },
                            // The live stream's Timeline button lands here. `Date()` is read as the
                            // push resolves, so the recordings open at the live edge — the moment
                            // the stream was showing.
                            cameraTimeline: { camera in
                                RecordingPlayerView(
                                    viewModel: composition.recordingPlayerViewModel(
                                        for: camera, at: Date(), connection: connection
                                    )
                                )
                            }
                        )
                    } label: {
                        Label("Cameras", systemImage: "video")
                            .symbolEffect(.bounce, value: iconBounces[.cameras])
                    }

                    Tab(value: AppTab.timeline) {
                        TimelineScreenView(
                            viewModel: composition.timelineScreenViewModel(for: connection),
                            makeTileViewModel: { composition.previewTileViewModel(for: $0, connection: connection) },
                            makeRecordingPlayerViewModel: {
                                composition.recordingPlayerViewModel(for: $0, at: $1, connection: connection)
                            }
                        )
                    } label: {
                        Label("Timeline", systemImage: "calendar.day.timeline.left")
                            .symbolEffect(.bounce, value: iconBounces[.timeline])
                    }

                    Tab(value: AppTab.events) {
                        EventsListView(
                            viewModel: composition.eventsListViewModel(for: connection),
                            onOpenSettings: { showingSettings = true },
                            makeDetailViewModel: { composition.eventDetailViewModel(for: $0, connection: connection) }
                        )
                    } label: {
                        Label("Events", systemImage: "bell")
                            .symbolEffect(.bounce, value: iconBounces[.events])
                    }
                }
                .id(identity(of: connection))
                .onChange(of: selectedTab) { iconBounces[selectedTab, default: 0] += 1 }
            } else {
                SettingsView(
                    viewModel: composition.settingsViewModel(),
                    makeServerSettingsViewModel: { composition.serverSettingsViewModel() },
                    makeCameraOrderViewModel: nil,
                    makeAppIconViewModel: appIconViewModelFactory,
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
                },
                makeAppIconViewModel: appIconViewModelFactory
            ) {
                showingSettings = false
                reload()
            }
            // macOS sheets size to their root content and don't grow when the inner
            // NavigationStack pushes a detail, so the drill-in camera list needs room reserved here.
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
            #endif
        }
        .onAppear(perform: reload)
    }

    /// `nil` where the system cannot swap the icon, which is what hides the row on macOS.
    private var appIconViewModelFactory: (() -> AppIconViewModel)? {
        composition.supportsAppIconChoice ? { composition.appIconViewModel() } : nil
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

private enum AppTab: Hashable {
    case cameras
    case timeline
    case events
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
