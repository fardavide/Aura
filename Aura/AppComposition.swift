import Foundation

import CamerasData
import CamerasDomain
import CamerasPresentation
import CommonFrigate
import CommonKeychain
import CommonNetwork
import EventsData
import EventsDomain
import EventsPresentation
import ExportsData
import ExportsDomain
import ExportsPresentation
import SettingsData
import SettingsDomain
import SettingsPresentation
import TimelineData
import TimelineDomain
import TimelinePresentation

/// The composition root: the one place the object graph is wired with explicit initializer
/// injection. It is built from the **resolved** `ActiveServer` rather than from the saved
/// `ConnectionSettings`, so nothing below it knows the connection carries two addresses.
@MainActor
final class AppComposition {
    private let settingsRepository: any SettingsRepository
    private let httpClient: any HttpClient
    private let downloadClient: any HttpDownloadClient
    private let appIconSwitcher = SystemAppIconSwitcher()
    private let networkPaths: any NetworkPathObserving = SystemNetworkPathObserver()
    /// One per connection, held here rather than built in `RootView.body`: a transfer must survive
    /// leaving the Exports tab, and a view model rebuilt on every body pass would lose it.
    private var downloadCenters: [String: DownloadCenter] = [:]
    /// How much history the Timeline scrolls over — the same on the tab and on one camera's
    /// detail, so a tile tapped at some instant opens onto the axis it was scrubbed on.
    private let timelineSpanDays = 7
    /// How long the local address gets to answer before the app settles on the remote one.
    ///
    /// A LAN round trip is tens of milliseconds, so this is roughly twenty times what a server
    /// that *is* there needs — generous enough to survive a sleepy Wi-Fi radio waking up, short
    /// enough that arriving at a café doesn't visibly delay the first screen. It is only ever
    /// paid on Wi-Fi with a local address configured; cellular resolves with no wait at all.
    private let localProbeTimeout = Duration.milliseconds(600)

    init() {
        settingsRepository = DefaultSettingsRepository(
            keychain: SystemKeychain(service: "fardavide.Aura")
        )
        httpClient = UrlSessionHttpClient()
        downloadClient = UrlSessionHttpDownloadClient()
    }

    func currentConnection() -> ConnectionSettings? {
        LoadConnection(repository: settingsRepository).execute()
    }

    func currentTheme() -> ThemePreference {
        LoadTheme(repository: settingsRepository).execute()
    }

    /// Streams the address to talk to now, and a new one whenever the device's network changes.
    func observeActiveServer() -> ObserveActiveServer {
        ObserveActiveServer(
            probe: FrigateServerProbe(httpClient: httpClient),
            networkPaths: networkPaths,
            localProbeTimeout: localProbeTimeout
        )
    }

    /// `server` is `nil` before one is configured — the menu then has no Camera Order row and
    /// nothing to count.
    func settingsViewModel(for server: ActiveServer?) -> SettingsViewModel {
        SettingsViewModel(
            loadTheme: LoadTheme(repository: settingsRepository),
            saveTheme: SaveTheme(repository: settingsRepository),
            loadConnection: LoadConnection(repository: settingsRepository),
            activeServer: server,
            loadDynamicCameraOrder: LoadDynamicCameraOrder(repository: settingsRepository),
            saveDynamicCameraOrder: SaveDynamicCameraOrder(repository: settingsRepository),
            getCameras: server.map { server in
                GetCameras(
                    repository: FrigateCamerasRepository(
                        configProvider: configProvider(config: ServerConfig(server))
                    )
                )
            },
            loadAppIcon: appIconSwitcher.isSupported ? LoadAppIcon(switcher: appIconSwitcher) : nil
        )
    }

    /// `false` where the system has no alternate icon to switch to, so Settings omits the row
    /// rather than offering a picker that fails on every tap.
    var supportsAppIconChoice: Bool {
        appIconSwitcher.isSupported
    }

    func appIconViewModel() -> AppIconViewModel {
        AppIconViewModel(
            loadAppIcon: LoadAppIcon(switcher: appIconSwitcher),
            changeAppIcon: ChangeAppIcon(switcher: appIconSwitcher)
        )
    }

    func serverSettingsViewModel() -> ServerSettingsViewModel {
        ServerSettingsViewModel(
            loadConnection: LoadConnection(repository: settingsRepository),
            saveConnection: SaveConnection(repository: settingsRepository)
        )
    }

    func cameraOrderViewModel(for server: ActiveServer) -> CameraOrderViewModel {
        CameraOrderViewModel(
            getCameras: GetCameras(
                repository: FrigateCamerasRepository(
                    configProvider: configProvider(config: ServerConfig(server))
                )
            ),
            loadCameraOrder: LoadCameraOrder(repository: settingsRepository),
            saveCameraOrder: SaveCameraOrder(repository: settingsRepository)
        )
    }

    func cameraGridViewModel(for server: ActiveServer) -> CameraGridViewModel {
        let config = ServerConfig(server)
        // One config read shared by the three things on this screen that need a slice of it — the
        // camera list, the group chips and the retention figures — instead of one heavy
        // `/api/config` GET each. It re-reads itself while the screen watches, so the chips and the
        // summary card follow a server-side change without a reload.
        let configProvider = configProvider(config: config)
        return CameraGridViewModel(
            observeCameras: observeCameras(configProvider: configProvider),
            observeDynamicCameraOrder: ObserveDynamicCameraOrder(repository: settingsRepository),
            getCameraActivity: GetCameraActivity(
                repository: FrigateCameraActivityRepository(config: config, httpClient: httpClient, now: { Date() })
            ),
            observeCameraGroups: ObserveCameraGroups(
                repository: FrigateCameraGroupsRepository(configProvider: configProvider)
            ),
            getTodayEventCounts: GetTodayEventCounts(
                repository: FrigateTodayEventsRepository(config: config, httpClient: httpClient),
                now: { Date() }
            ),
            observeRecordingStorage: ObserveRecordingStorage(
                repository: FrigateRecordingStorageRepository(
                    config: config, httpClient: httpClient, configProvider: configProvider
                )
            ),
            imageLoader: FrigateCameraImageLoader(config: config, httpClient: httpClient)
        )
    }

    func cameraDetailViewModel(
        for camera: Camera,
        server: ActiveServer
    ) -> CameraDetailViewModel {
        CameraDetailViewModel(
            camera: camera,
            streamProvider: FrigateCameraStreamProvider(config: ServerConfig(server))
        )
    }

    func eventsListViewModel(for server: ActiveServer) -> EventsListViewModel {
        let config = ServerConfig(server)
        return EventsListViewModel(
            getEvents: GetEvents(
                repository: FrigateEventsRepository(config: config, httpClient: httpClient)
            ),
            // Friendly camera names for the rows and the hero — the same `/api/config` read the
            // other tabs use, scoped to this screen's lifetime.
            getCameras: GetCameras(
                repository: FrigateCamerasRepository(configProvider: configProvider(config: config))
            ),
            thumbnailLoader: FrigateEventThumbnailLoader(config: config, httpClient: httpClient),
            snapshotLoader: FrigateEventSnapshotLoader(config: config, httpClient: httpClient),
            now: { Date() },
            calendar: .current
        )
    }

    func eventDetailViewModel(
        for event: Event,
        server: ActiveServer
    ) -> EventDetailViewModel {
        let config = ServerConfig(server)
        let repository = FrigateEventsRepository(config: config, httpClient: httpClient)
        return EventDetailViewModel(
            event: event,
            clipLoader: FrigateEventClipLoader(config: config, httpClient: httpClient),
            getEvent: GetEvent(repository: repository),
            isDetectionFeedbackEnabled: IsDetectionFeedbackEnabled(repository: repository),
            submitDetectionVerdict: SubmitDetectionVerdict(repository: repository)
        )
    }

    func exportsListViewModel(for server: ActiveServer) -> ExportsListViewModel {
        let config = ServerConfig(server)
        return ExportsListViewModel(
            getExports: GetExports(
                repository: FrigateExportsRepository(config: config, httpClient: httpClient)
            ),
            // Friendly camera names on the cards — the same shared `/api/config` read the other
            // tabs use.
            getCameras: GetCameras(
                repository: FrigateCamerasRepository(configProvider: configProvider(config: config))
            ),
            thumbnailLoader: FrigateExportThumbnailLoader(config: config, httpClient: httpClient),
            serverLabel: "\(server.address.host):\(server.address.port)",
            now: { Date() },
            calendar: .current,
            processingPollInterval: .seconds(15),
            minimumRetryDuration: .milliseconds(600),
            refreshIndicatorDelay: .milliseconds(400)
        )
    }

    func downloadCenter(for server: ActiveServer) -> DownloadCenter {
        let key = identity(of: server)
        if let existing = downloadCenters[key] { return existing }
        let center = DownloadCenter(
            downloadExport: DownloadExport(
                downloader: FrigateExportDownloader(
                    config: ServerConfig(server),
                    downloadClient: downloadClient
                )
            ),
            cancelledNoticeDuration: .seconds(3)
        )
        downloadCenters[key] = center
        return center
    }

    func exportPlayerViewModel(for export: Export, server: ActiveServer) -> ExportPlayerViewModel {
        ExportPlayerViewModel(
            export: export,
            playback: FrigateExportPlaybackProvider(config: ServerConfig(server))
        )
    }

    func timelineScreenViewModel(for server: ActiveServer) -> TimelineScreenViewModel {
        let config = ServerConfig(server)
        return TimelineScreenViewModel(
            observeCameras: observeCameras(configProvider: configProvider(config: config)),
            observeDynamicCameraOrder: ObserveDynamicCameraOrder(repository: settingsRepository),
            getDayTimeline: GetDayTimeline(
                repository: FrigateCameraDayTimelineRepository(config: config, httpClient: httpClient)
            ),
            now: { Date() },
            days: timelineSpanDays
        )
    }

    func previewTileViewModel(for camera: Camera, server: ActiveServer) -> PreviewTileViewModel {
        let config = ServerConfig(server)
        return PreviewTileViewModel(
            camera: camera,
            previews: GetCameraPreviews(
                provider: FrigatePreviewSourceProvider(config: config, httpClient: httpClient)
            ),
            recordings: GetCameraRecordings(
                repository: FrigateCameraRecordingsRepository(config: config, httpClient: httpClient)
            ),
            imageLoader: FrigatePreviewImageLoader(config: config, httpClient: httpClient)
        )
    }

    func recordingPlayerViewModel(
        for camera: Camera,
        at instant: Date,
        server: ActiveServer
    ) -> RecordingPlayerViewModel {
        let config = ServerConfig(server)
        let recordings = GetCameraRecordings(
            repository: FrigateCameraRecordingsRepository(config: config, httpClient: httpClient)
        )
        let previews = GetCameraPreviews(
            provider: FrigatePreviewSourceProvider(config: config, httpClient: httpClient)
        )
        let imageLoader = FrigatePreviewImageLoader(config: config, httpClient: httpClient)
        // The range selector submits from this screen, so it gets the two use cases — never the
        // repository behind them.
        let exports = FrigateExportsRepository(config: config, httpClient: httpClient)
        return RecordingPlayerViewModel(
            camera: camera,
            recordings: recordings,
            // Scoped to this camera, unlike the tab's all-camera read — the detail timeline shows
            // one camera's activity, not the deployment's.
            getDayTimeline: GetDayTimeline(
                repository: FrigateCameraDayTimelineRepository(config: config, httpClient: httpClient)
            ),
            createExport: CreateExport(repository: exports),
            getExport: GetExport(repository: exports),
            filmstrip: RecordingFilmstripStore(
                camera: camera.name,
                previews: previews,
                imageLoader: imageLoader
            ),
            scrubPreview: PreviewTileViewModel(
                camera: camera,
                previews: previews,
                recordings: recordings,
                imageLoader: imageLoader
            ),
            liveSource: FrigateCameraStreamProvider(config: config).streamSource(for: camera),
            now: { Date() },
            startingAt: instant,
            days: timelineSpanDays
        )
    }

    /// Keys the per-server singletons above, and the root's tab tree. It carries the resolved
    /// **address**, so switching between the local and the remote route starts a fresh set rather
    /// than reusing transfers bound to an address that is no longer reachable.
    func identity(of server: ActiveServer) -> String {
        "\(server.address.scheme.rawValue)://\(server.address.host):\(server.address.port)"
    }

    private func observeCameras(configProvider: FrigateConfigProvider) -> ObserveCameras {
        ObserveCameras(
            getCameras: GetCameras(
                repository: FrigateCamerasRepository(configProvider: configProvider)
            ),
            observeCameraOrder: ObserveCameraOrder(repository: settingsRepository)
        )
    }

    /// A config reader for one screen's lifetime. Screens don't share one: each builds its own, so
    /// the periodic re-read lives and dies with the screen watching it.
    private func configProvider(config: ServerConfig) -> FrigateConfigProvider {
        FrigateConfigProvider(
            config: config,
            httpClient: httpClient,
            refreshInterval: .seconds(120)
        )
    }
}
