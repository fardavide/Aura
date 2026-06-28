import Foundation
import Observation

import SettingsDomain

@Observable
@MainActor
public final class SettingsViewModel {
    public var scheme: ConnectionSettings.Scheme = .http
    public var host: String = ""
    public var port: String = "5000"
    public var username: String = ""
    public var password: String = ""
    public var theme: ThemePreference = .system

    public private(set) var errorMessage: String?
    public private(set) var didSave = false

    private let loadConnection: LoadConnection
    private let saveConnection: SaveConnection
    private let loadTheme: LoadTheme
    private let saveTheme: SaveTheme

    public init(
        loadConnection: LoadConnection,
        saveConnection: SaveConnection,
        loadTheme: LoadTheme,
        saveTheme: SaveTheme
    ) {
        self.loadConnection = loadConnection
        self.saveConnection = saveConnection
        self.loadTheme = loadTheme
        self.saveTheme = saveTheme
    }

    public func onAppear() {
        if let connection = loadConnection.execute() {
            scheme = connection.scheme
            host = connection.host
            port = String(connection.port)
            username = connection.username ?? ""
            password = connection.password ?? ""
        }
        theme = loadTheme.execute()
    }

    public func save() {
        errorMessage = nil
        didSave = false
        guard let portValue = Int(port) else {
            errorMessage = "Port must be a number."
            return
        }
        let settings = ConnectionSettings(
            scheme: scheme,
            host: host,
            port: portValue,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password
        )
        do {
            try saveConnection.execute(settings)
            saveTheme.execute(theme)
            didSave = true
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: SettingsError) -> String {
        switch error {
        case .invalidHost: "Enter a valid host."
        case .invalidPort: "Port must be between 1 and 65535."
        }
    }
}
