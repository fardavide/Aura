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
/// injection, and where the domain `ConnectionSettings` is mapped to the infra `ServerConfig`.
@MainActor
final class AppComposition {
    private let settingsRepository: any SettingsRepository
    private let httpClient: any HttpClient
    private let downloadClient: any HttpDownloadClient
    private let appIconSwitcher = SystemAppIconSwitcher()
    /// One per connection, held here rather than built in `RootView.body`: a transfer must survive
    /// leaving the Exports tab, and a view model rebuilt on every body pass would lose it.
    private var downloadCenters: [String: DownloadCenter] = [:]
    /// How much history the Timeline scrolls over — the same on the tab and on one camera's
    /// detail, so a tile tapped at some instant opens onto the axis it was scrubbed on.
    private let timelineSpanDays = 7

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

    /// `connection` is `nil` before a server is configured — the menu then has no Camera Order
    /// row and nothing to count.
    func settingsViewModel(for connection: ConnectionSettings?) -> SettingsViewModel {
        SettingsViewModel(
            loadTheme: LoadTheme(repository: settingsRepository),
            saveTheme: SaveTheme(repository: settingsRepository),
            loadConnection: LoadConnection(repository: settingsRepository),
            loadDynamicCameraOrder: LoadDynamicCameraOrder(repository: settingsRepository),
            saveDynamicCameraOrder: SaveDynamicCameraOrder(repository: settingsRepository),
            getCameras: connection.map { connection in
                GetCameras(
                    repository: FrigateCamerasRepository(
                        configProvider: configProvider(config: serverConfig(from: connection))
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

    func cameraOrderViewModel(for connection: ConnectionSettings) -> CameraOrderViewModel {
        CameraOrderViewModel(
            getCameras: GetCameras(
                repository: FrigateCamerasRepository(
                    configProvider: configProvider(config: serverConfig(from: connection))
                )
            ),
            loadCameraOrder: LoadCameraOrder(repository: settingsRepository),
            saveCameraOrder: SaveCameraOrder(repository: settingsRepository)
        )
    }

    func cameraGridViewModel(for connection: ConnectionSettings) -> CameraGridViewModel {
        let config = serverConfig(from: connection)
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
        connection: ConnectionSettings
    ) -> CameraDetailViewModel {
        CameraDetailViewModel(
            camera: camera,
            streamProvider: FrigateCameraStreamProvider(config: serverConfig(from: connection))
        )
    }

    func eventsListViewModel(for connection: ConnectionSettings) -> EventsListViewModel {
        let config = serverConfig(from: connection)
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
        connection: ConnectionSettings
    ) -> EventDetailViewModel {
        let config = serverConfig(from: connection)
        let repository = FrigateEventsRepository(config: config, httpClient: httpClient)
        return EventDetailViewModel(
            event: event,
            clipLoader: FrigateEventClipLoader(config: config, httpClient: httpClient),
            getEvent: GetEvent(repository: repository),
            isDetectionFeedbackEnabled: IsDetectionFeedbackEnabled(repository: repository),
            submitDetectionVerdict: SubmitDetectionVerdict(repository: repository)
        )
    }

    func exportsListViewModel(for connection: ConnectionSettings) -> ExportsListViewModel {
        let config = serverConfig(from: connection)
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
            serverLabel: "\(connection.host):\(connection.port)",
            now: { Date() },
            calendar: .current,
            processingPollInterval: .seconds(15),
            minimumRetryDuration: .milliseconds(600),
            refreshIndicatorDelay: .milliseconds(400)
        )
    }

    func downloadCenter(for connection: ConnectionSettings) -> DownloadCenter {
        let key = identity(of: connection)
        if let existing = downloadCenters[key] { return existing }
        let center = DownloadCenter(
            downloadExport: DownloadExport(
                downloader: FrigateExportDownloader(
                    config: serverConfig(from: connection),
                    downloadClient: downloadClient
                )
            ),
            cancelledNoticeDuration: .seconds(3)
        )
        downloadCenters[key] = center
        return center
    }

    func exportPlayerViewModel(for export: Export, connection: ConnectionSettings) -> ExportPlayerViewModel {
        ExportPlayerViewModel(
            export: export,
            playback: FrigateExportPlaybackProvider(config: serverConfig(from: connection))
        )
    }

    func timelineScreenViewModel(for connection: ConnectionSettings) -> TimelineScreenViewModel {
        let config = serverConfig(from: connection)
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

    func previewTileViewModel(for camera: Camera, connection: ConnectionSettings) -> PreviewTileViewModel {
        let config = serverConfig(from: connection)
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
        connection: ConnectionSettings
    ) -> RecordingPlayerViewModel {
        let config = serverConfig(from: connection)
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

    /// Keys the per-connection singletons above. Pointing the app at a different server starts a
    /// fresh set rather than inheriting the previous server's transfers.
    private func identity(of connection: ConnectionSettings) -> String {
        "\(connection.scheme.rawValue)://\(connection.host):\(connection.port)"
    }

    private func serverConfig(from connection: ConnectionSettings) -> ServerConfig {
        let scheme: ServerConfig.Scheme = switch connection.scheme {
        case .http: .http
        case .https: .https
        }
        return ServerConfig(
            scheme: scheme,
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: connection.password
        )
    }
}
