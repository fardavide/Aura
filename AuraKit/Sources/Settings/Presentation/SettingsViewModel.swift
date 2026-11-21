import Foundation
import Observation

import CamerasDomain
import SettingsDomain

@Observable
@MainActor
public final class SettingsViewModel {
    public enum ServerSummary: Equatable, Sendable {
        case notConfigured
        /// `route` is `nil` when only one address is configured: there was no choice to make, and
        /// a permanent "REMOTE" tag would read as a setting rather than as a fact about right now.
        case configured(hostPort: String, route: ServerRoute?)
    }

    public enum CameraCount: Equatable, Sendable {
        case unknown
        case known(Int)
    }

    /// Saved on every change — no explicit save step on the main settings screen.
    public var theme: ThemePreference = .system {
        didSet { saveTheme.execute(theme) }
    }
    /// Whether the camera walls may promote the newest alert's camera ahead of the saved order.
    /// Saved on every change, like `theme`; the walls observe the preference and re-settle on their
    /// own rather than waiting for the sheet to be dismissed.
    public var usesDynamicCameraOrder = true {
        didSet { saveDynamicCameraOrder.execute(usesDynamicCameraOrder) }
    }
    public private(set) var serverSummary: ServerSummary = .notConfigured
    public private(set) var cameraCount: CameraCount = .unknown

    /// `nil` while the count is unknown — the Camera Order row omits its trailing value rather
    /// than showing a placeholder.
    public var cameraCountText: String? {
        guard case let .known(count) = cameraCount else { return nil }
        return count == 1 ? "1 camera" : "\(count) cameras"
    }

    private let loadTheme: LoadTheme
    private let saveTheme: SaveTheme
    private let loadConnection: LoadConnection
    /// The address resolved by the root, if it has opened a connection yet.
    private let activeServer: ActiveServer?
    private let loadDynamicCameraOrder: LoadDynamicCameraOrder
    private let saveDynamicCameraOrder: SaveDynamicCameraOrder
    /// `nil` before a connection is configured — the menu has no Camera Order row and nothing
    /// to count.
    private let getCameras: GetCameras?

    public init(
        loadTheme: LoadTheme,
        saveTheme: SaveTheme,
        loadConnection: LoadConnection,
        activeServer: ActiveServer?,
        loadDynamicCameraOrder: LoadDynamicCameraOrder,
        saveDynamicCameraOrder: SaveDynamicCameraOrder,
        getCameras: GetCameras?
    ) {
        self.loadTheme = loadTheme
        self.saveTheme = saveTheme
        self.loadConnection = loadConnection
        self.activeServer = activeServer
        self.loadDynamicCameraOrder = loadDynamicCameraOrder
        self.saveDynamicCameraOrder = saveDynamicCameraOrder
        self.getCameras = getCameras
    }

    public func onAppear() {
        theme = loadTheme.execute()
        usesDynamicCameraOrder = loadDynamicCameraOrder.execute()
        refreshServerSummary()
    }

    func refreshServerSummary() {
        guard let connection = loadConnection.execute() else {
            serverSummary = .notConfigured
            return
        }

        let currentServer: ActiveServer? = if let activeServer,
            activeServer == connection.remoteServer || activeServer == connection.localServer {
            activeServer
        } else {
            nil
        }
        let address = currentServer?.address ?? connection.fallbackServer.address
        let route: ServerRoute? = if case .both = connection.addresses { currentServer?.route } else { nil }
        serverSummary = .configured(
            hostPort: "\(address.host):\(address.port)",
            route: route
        )
    }

    public func load() async {
        guard let getCameras else { return }
        do {
            cameraCount = .known(try await getCameras.execute().count)
        } catch {
            // Keep the last known count (`.unknown` on a first failure, the previous `.known` on
            // a failed refresh) — the pushed Camera Order screen owns explaining the failure.
        }
    }
}
