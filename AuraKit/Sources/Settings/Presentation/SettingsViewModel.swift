import Foundation
import Observation

import CamerasDomain
import SettingsDomain

@Observable
@MainActor
public final class SettingsViewModel {
    public enum ServerSummary: Equatable, Sendable {
        case notConfigured
        case configured(hostPort: String)
    }

    public enum CameraCount: Equatable, Sendable {
        case unknown
        case known(Int)
    }

    /// Saved on every change — no explicit save step on the main settings screen.
    public var theme: ThemePreference = .system {
        didSet { saveTheme.execute(theme) }
    }
    public private(set) var serverSummary: ServerSummary = .notConfigured
    public private(set) var cameraCount: CameraCount = .unknown
    /// `nil` where the platform has no swappable app icon — the row is absent, matching
    /// `loadAppIcon == nil`.
    public private(set) var appIcon: AppIconPreference?

    /// `nil` while the count is unknown — the Camera Order row omits its trailing value rather
    /// than showing a placeholder.
    public var cameraCountText: String? {
        guard case let .known(count) = cameraCount else { return nil }
        return count == 1 ? "1 camera" : "\(count) cameras"
    }

    private let loadTheme: LoadTheme
    private let saveTheme: SaveTheme
    private let loadConnection: LoadConnection
    /// `nil` before a connection is configured — the menu has no Camera Order row and nothing
    /// to count.
    private let getCameras: GetCameras?
    /// `nil` where the platform cannot switch icons — mirrors `makeAppIconViewModel == nil`.
    private let loadAppIcon: LoadAppIcon?

    public init(
        loadTheme: LoadTheme,
        saveTheme: SaveTheme,
        loadConnection: LoadConnection,
        getCameras: GetCameras?,
        loadAppIcon: LoadAppIcon?
    ) {
        self.loadTheme = loadTheme
        self.saveTheme = saveTheme
        self.loadConnection = loadConnection
        self.getCameras = getCameras
        self.loadAppIcon = loadAppIcon
    }

    public func onAppear() {
        theme = loadTheme.execute()
        serverSummary = if let connection = loadConnection.execute() {
            .configured(hostPort: "\(connection.host):\(connection.port)")
        } else {
            .notConfigured
        }
        appIcon = loadAppIcon?.execute()
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
