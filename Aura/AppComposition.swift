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

    func settingsViewModel() -> SettingsViewModel {
        SettingsViewModel(
            loadTheme: LoadTheme(repository: settingsRepository),
            saveTheme: SaveTheme(repository: settingsRepository)
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
                repository: FrigateCamerasRepository(config: serverConfig(from: connection), httpClient: httpClient)
            ),
            loadCameraOrder: LoadCameraOrder(repository: settingsRepository),
            saveCameraOrder: SaveCameraOrder(repository: settingsRepository)
        )
    }

    func cameraGridViewModel(for connection: ConnectionSettings) -> CameraGridViewModel {
        let config = serverConfig(from: connection)
        return CameraGridViewModel(
            observeCameras: observeCameras(config: config),
            getCameraActivity: GetCameraActivity(
                repository: FrigateCameraActivityRepository(config: config, httpClient: httpClient, now: { Date() })
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
            observeCameras: observeCameras(config: config),
            getDayTimeline: GetDayTimeline(
                repository: FrigateCameraDayTimelineRepository(config: config, httpClient: httpClient)
            ),
            now: { Date() },
            days: 7
        )
    }

    func previewTileViewModel(for camera: Camera, connection: ConnectionSettings) -> PreviewTileViewModel {
        let config = serverConfig(from: connection)
        return PreviewTileViewModel(
            camera: camera,
            previews: GetCameraPreviews(
                provider: FrigatePreviewSourceProvider(config: config, httpClient: httpClient)
            ),
            imageLoader: FrigatePreviewImageLoader(config: config, httpClient: httpClient)
        )
    }

    private func observeCameras(config: ServerConfig) -> ObserveCameras {
        ObserveCameras(
            getCameras: GetCameras(
                repository: FrigateCamerasRepository(config: config, httpClient: httpClient)
            ),
            observeCameraOrder: ObserveCameraOrder(repository: settingsRepository)
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
