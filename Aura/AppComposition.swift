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
    private let appIconSwitcher = SystemAppIconSwitcher()
    /// How much history the Timeline scrolls over — the same on the tab and on one camera's
    /// detail, so a tile tapped at some instant opens onto the axis it was scrubbed on.
    private let timelineSpanDays = 7

    init() {
        settingsRepository = DefaultSettingsRepository(
            keychain: SystemKeychain(service: "fardavide.Aura")
        )
        httpClient = UrlSessionHttpClient()
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
            thumbnailLoader: FrigateEventThumbnailLoader(config: config, httpClient: httpClient)
        )
    }

    func eventDetailViewModel(
        for event: Event,
        connection: ConnectionSettings
    ) -> EventDetailViewModel {
        EventDetailViewModel(
            event: event,
            clipLoader: FrigateEventClipLoader(config: serverConfig(from: connection), httpClient: httpClient)
        )
    }

    func timelineScreenViewModel(for connection: ConnectionSettings) -> TimelineScreenViewModel {
        let config = serverConfig(from: connection)
        return TimelineScreenViewModel(
            observeCameras: observeCameras(configProvider: configProvider(config: config)),
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
        return RecordingPlayerViewModel(
            camera: camera,
            recordings: GetCameraRecordings(
                repository: FrigateCameraRecordingsRepository(config: config, httpClient: httpClient)
            ),
            // Scoped to this camera, unlike the tab's all-camera read — the detail timeline shows
            // one camera's activity, not the deployment's.
            getDayTimeline: GetDayTimeline(
                repository: FrigateCameraDayTimelineRepository(config: config, httpClient: httpClient)
            ),
            filmstrip: RecordingFilmstripStore(
                camera: camera.name,
                previews: GetCameraPreviews(
                    provider: FrigatePreviewSourceProvider(config: config, httpClient: httpClient)
                ),
                imageLoader: FrigatePreviewImageLoader(config: config, httpClient: httpClient)
            ),
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
