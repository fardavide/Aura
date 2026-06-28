import CamerasData
import CamerasDomain
import CamerasPresentation
import CommonFrigate
import CommonKeychain
import CommonNetwork
import SettingsData
import SettingsDomain
import SettingsPresentation

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
            loadConnection: LoadConnection(repository: settingsRepository),
            saveConnection: SaveConnection(repository: settingsRepository),
            loadTheme: LoadTheme(repository: settingsRepository),
            saveTheme: SaveTheme(repository: settingsRepository)
        )
    }

    func cameraGridViewModel(for connection: ConnectionSettings) -> CameraGridViewModel {
        let config = serverConfig(from: connection)
        return CameraGridViewModel(
            getCameras: GetCameras(
                repository: FrigateCamerasRepository(config: config, httpClient: httpClient)
            ),
            imageLoader: FrigateCameraImageLoader(config: config, httpClient: httpClient)
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
