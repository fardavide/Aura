import Foundation
import Synchronization

import CamerasEntities
import CommonKeychain
import SettingsDomain

/// Persists settings by splitting storage: non-secret values in `UserDefaults`, the password
/// in the Keychain. The password never touches `UserDefaults`.
public struct DefaultSettingsRepository: SettingsRepository, @unchecked Sendable {
    private let defaults: UserDefaults
    private let keychain: any KeychainStore
    private let observers = CameraOrderObservers()

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

    public func loadCameraOrder() -> [CameraName] {
        defaults.stringArray(forKey: Keys.cameraOrder)?.map(CameraName.init) ?? []
    }

    public func saveCameraOrder(_ order: [CameraName]) {
        defaults.set(order.map(\.value), forKey: Keys.cameraOrder)
        observers.yield(order)
    }

    public func observeCameraOrder() -> AsyncStream<[CameraName]> {
        AsyncStream { continuation in
            let id = observers.register(continuation, seededWith: loadCameraOrder)
            continuation.onTermination = { [observers] _ in observers.remove(id) }
        }
    }

    private func write(_ value: String?, toDefaultsKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// A reference type so every copy of the repository value shares the one observer set.
private final class CameraOrderObservers: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<[CameraName]>.Continuation]>([:])

    /// Seeding and registration happen under the one lock that `yield` also takes, so a
    /// concurrent save is either visible to the seed read or delivered to the registered
    /// continuation — never lost between the two.
    func register(
        _ continuation: AsyncStream<[CameraName]>.Continuation,
        seededWith currentOrder: () -> [CameraName]
    ) -> UUID {
        let id = UUID()
        continuations.withLock {
            continuation.yield(currentOrder())
            $0[id] = continuation
        }
        return id
    }

    func remove(_ id: UUID) {
        continuations.withLock { _ = $0.removeValue(forKey: id) }
    }

    func yield(_ order: [CameraName]) {
        let active = continuations.withLock { Array($0.values) }
        for continuation in active {
            continuation.yield(order)
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
    static let cameraOrder = "cameraOrder"
}
