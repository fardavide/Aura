import Foundation

import CommonKeychain
import SettingsDomain

/// Persists settings by splitting storage: non-secret values in `UserDefaults`, the password
/// in the Keychain. The password never touches `UserDefaults`.
public struct DefaultSettingsRepository: SettingsRepository, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keychain: any KeychainStore

    public init(defaults: UserDefaults = .standard, keychain: any KeychainStore) {
        self.defaults = defaults
        self.keychain = keychain
    }

    public func loadConnection() -> ConnectionSettings? {
        guard
            let host = defaults.string(forKey: Keys.host),
            let schemeRaw = defaults.string(forKey: Keys.scheme),
            let scheme = ConnectionSettings.Scheme(rawValue: schemeRaw)
        else {
            return nil
        }
        return ConnectionSettings(
            scheme: scheme,
            host: host,
            port: defaults.integer(forKey: Keys.port),
            username: defaults.string(forKey: Keys.username),
            password: keychain.string(for: Keys.password)
        )
    }

    public func saveConnection(_ settings: ConnectionSettings) {
        defaults.set(settings.scheme.rawValue, forKey: Keys.scheme)
        defaults.set(settings.host, forKey: Keys.host)
        defaults.set(settings.port, forKey: Keys.port)
        write(settings.username, toDefaultsKey: Keys.username)
        keychain.set(settings.password, for: Keys.password)
    }

    public func loadTheme() -> ThemePreference {
        defaults.string(forKey: Keys.theme).flatMap(ThemePreference.init(rawValue:)) ?? .system
    }

    public func saveTheme(_ theme: ThemePreference) {
        defaults.set(theme.rawValue, forKey: Keys.theme)
    }

    private func write(_ value: String?, toDefaultsKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

private enum Keys {
    static let scheme = "connection.scheme"
    static let host = "connection.host"
    static let port = "connection.port"
    static let username = "connection.username"
    static let password = "connection.password"
    static let theme = "theme"
}
