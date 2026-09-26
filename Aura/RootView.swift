import SwiftUI

import CamerasDomain
import CamerasPresentation
import CommonDesign
import EventsDomain
import EventsPresentation
import ExportsPresentation
import SettingsDomain
import SettingsPresentation
import TimelinePresentation

/// Routes between the camera grid (when a connection is configured) and Settings, and applies
/// the chosen theme. Reloads its config whenever Settings reports a save, and follows the
/// resolved server address so joining or leaving the home network re-points the whole app.
struct RootView: View {
    let composition: AppComposition

    @State private var connection: ConnectionSettings?
    /// The address in use. `nil` only while the very first resolution is in flight — at most one
    /// short local probe, and not even that when there is no local address to try.
    @State private var server: ActiveServer?
    @State private var theme: ThemePreference = .system
    @State private var showingSettings = false
    @State private var selectedTab = AppTab.cameras
    // Bumped per tab on selection so only the newly selected icon bounces — keying the
    // effect on `selectedTab == tab` would also bounce the icon being deselected.
    @State private var iconBounces: [AppTab: Int] = [:]

    var body: some View {
        Group {
            if let server {
                TabView(selection: $selectedTab) {
                    Tab(value: AppTab.cameras) {
                        CameraGridView(
                            viewModel: composition.cameraGridViewModel(for: server),
                            onOpenSettings: { showingSettings = true },
                            makeDetailViewModel: { composition.cameraDetailViewModel(for: $0, server: server) },
                            // The live stream's Timeline button lands here. `Date()` is read as the
                            // push resolves, so the recordings open at the live edge — the moment
                            // the stream was showing.
                            cameraTimeline: { camera in
                                RecordingPlayerView(
                                    viewModel: composition.recordingPlayerViewModel(
                                        for: camera, at: Date(), server: server
                                    ),
                                    onOpenExports: { selectedTab = .exports }
                                )
                            }
                        )
                        .modifier(TabEntrance())
                    } label: {
                        Label("Cameras", systemImage: "video")
                            .symbolEffect(.bounce, value: iconBounces[.cameras])
                    }

                    Tab(value: AppTab.timeline) {
                        TimelineScreenView(
                            viewModel: composition.timelineScreenViewModel(for: server),
                            makeTileViewModel: { composition.previewTileViewModel(for: $0, server: server) },
                            makeRecordingPlayerViewModel: {
                                composition.recordingPlayerViewModel(for: $0, at: $1, server: server)
                            },
                            onOpenSettings: { showingSettings = true },
                            // A clip cut on the detail screen lands in the Exports tab, and the
                            // detail screen hides the tab bar — so the way across is this.
                            onOpenExports: { selectedTab = .exports }
                        )
                        .modifier(TabEntrance())
                    } label: {
                        Label("Timeline", systemImage: "calendar.day.timeline.left")
                            .symbolEffect(.bounce, value: iconBounces[.timeline])
                    }

                    Tab(value: AppTab.events) {
                        EventsListView(
                            viewModel: composition.eventsListViewModel(for: server),
                            onOpenSettings: { showingSettings = true },
                            makeDetailViewModel: { composition.eventDetailViewModel(for: $0, server: server) }
                        )
                        .modifier(TabEntrance())
                    } label: {
                        Label("Events", systemImage: "bell")
                            .symbolEffect(.bounce, value: iconBounces[.events])
                    }

                    Tab(value: AppTab.exports) {
                        ExportsListView(
                            viewModel: composition.exportsListViewModel(for: server),
                            downloads: composition.downloadCenter(for: server),
                            onOpenSettings: { showingSettings = true },
                            // The empty state's only control, and it has to do something the user
                            // can perceive — selecting the tab where clips will be cut.
                            onOpenTimeline: { selectedTab = .timeline },
                            makePlayerViewModel: {
                                composition.exportPlayerViewModel(for: $0, server: server)
                            }
                        )
                        .modifier(TabEntrance())
                    } label: {
                        Label("Exports", systemImage: "film.stack")
                            .symbolEffect(.bounce, value: iconBounces[.exports])
                    }
                }
                .id(composition.identity(of: server))
                .onChange(of: selectedTab) { iconBounces[selectedTab, default: 0] += 1 }
            } else if connection == nil {
                SettingsView(
                    viewModel: composition.settingsViewModel(for: nil),
                    makeServerSettingsViewModel: { composition.serverSettingsViewModel() },
                    makeCameraOrderViewModel: nil,
                    makeAppIconViewModel: appIconViewModelFactory,
                    onDone: reload
                )
            } else {
                connectingView
            }
        }
        .preferredColorScheme(theme.colorScheme)
        .sheet(isPresented: $showingSettings, onDismiss: reload) {
            SettingsView(
                viewModel: composition.settingsViewModel(for: server),
                makeServerSettingsViewModel: { composition.serverSettingsViewModel() },
                makeCameraOrderViewModel: server.map { server in
                    { composition.cameraOrderViewModel(for: server) }
                },
                makeAppIconViewModel: appIconViewModelFactory
            ) {
                showingSettings = false
            }
            .auroraSettingsSheet()
            // macOS sheets size to their root content and don't grow when the inner
            // NavigationStack pushes a detail, so the drill-in camera list needs room reserved here.
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 560)
            #endif
        }
        .onAppear(perform: reload)
        .task(id: connection) { await followActiveServer() }
    }

    /// Shown only while the first address is being chosen, which is a fraction of a second — but
    /// it is a real state, so it says what it is doing instead of showing a bare spinner.
    private var connectingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Finding your server…")
                .auroraText(.caption)
                .foregroundStyle(.auroraTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .auroraBackground()
    }

    /// `nil` where the system cannot swap the icon, which is what hides the row on macOS.
    private var appIconViewModelFactory: (() -> AppIconViewModel)? {
        composition.supportsAppIconChoice ? { composition.appIconViewModel() } : nil
    }

    private func reload() {
        connection = composition.currentConnection()
        theme = composition.currentTheme()
    }

    /// Re-keyed on the saved connection, so editing the server restarts the resolution; within one
    /// connection the stream keeps running and re-points the app whenever the network changes.
    private func followActiveServer() async {
        guard let connection else {
            server = nil
            return
        }
        // Deliberately does *not* blank `server` first: re-resolving on every Settings dismissal
        // would otherwise tear down the whole tab tree — and any playback in it — for the
        // milliseconds the new answer takes to land.
        for await resolved in composition.observeActiveServer().execute(for: connection) {
            server = resolved
        }
    }
}

/// `TabView` swaps its pages with no animation of its own, and the outgoing page is gone the frame
/// the selection changes — so the incoming page is the only half of a switch that can move. It
/// fades in on every appearance, a first visit and a return alike; pushes inside a tab's own
/// navigation stack don't disappear the page, so they never re-trigger it.
private struct TabEntrance: ViewModifier {
    @State private var isShown = false

    func body(content: Content) -> some View {
        content
            .opacity(isShown ? 1 : 0)
            .onAppear { withAnimation(.auroraTabSwitch) { isShown = true } }
            .onDisappear { isShown = false }
    }
}

private enum AppTab: Hashable {
    case cameras
    case timeline
    case events
    case exports
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
