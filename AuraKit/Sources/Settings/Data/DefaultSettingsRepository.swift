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
    private let cameraOrderObservers = PreferenceObservers<[CameraName]>()
    private let dynamicCameraOrderObservers = PreferenceObservers<Bool>()

    public init(defaults: UserDefaults = .standard, keychain: any KeychainStore) {
        self.defaults = defaults
        self.keychain = keychain
    }

    /// The remote address keeps the original single-address keys, so an install that predates the
    /// local address keeps its server and simply reports no local one.
    public func loadConnection() -> ConnectionSettings? {
        guard let remote = address(at: Keys.remote) else { return nil }
        return ConnectionSettings(
            remote: remote,
            local: address(at: Keys.local),
            username: defaults.string(forKey: Keys.username),
            password: keychain.string(for: Keys.password)
        )
    }

    public func saveConnection(_ settings: ConnectionSettings) {
        write(settings.remote, to: Keys.remote)
        write(settings.local, to: Keys.local)
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
        cameraOrderObservers.yield(order)
    }

    public func observeCameraOrder() -> AsyncStream<[CameraName]> {
        AsyncStream { continuation in
            let id = cameraOrderObservers.register(continuation, seededWith: loadCameraOrder)
            continuation.onTermination = { [cameraOrderObservers] _ in cameraOrderObservers.remove(id) }
        }
    }

    /// Absent means on: the alert-led wall is the shipped behaviour, and an untouched install
    /// must not read as "turned off" just because `UserDefaults` answers `false` for a missing key.
    public func loadDynamicCameraOrder() -> Bool {
        guard defaults.object(forKey: Keys.dynamicCameraOrder) != nil else { return true }
        return defaults.bool(forKey: Keys.dynamicCameraOrder)
    }

    public func saveDynamicCameraOrder(_ isEnabled: Bool) {
        defaults.set(isEnabled, forKey: Keys.dynamicCameraOrder)
        dynamicCameraOrderObservers.yield(isEnabled)
    }

    public func observeDynamicCameraOrder() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            let id = dynamicCameraOrderObservers.register(continuation, seededWith: loadDynamicCameraOrder)
            continuation.onTermination = { [dynamicCameraOrderObservers] _ in
                dynamicCameraOrderObservers.remove(id)
            }
        }
    }

    private func address(at keys: Keys.Address) -> ServerAddress? {
        guard
            let host = defaults.string(forKey: keys.host),
            let schemeRaw = defaults.string(forKey: keys.scheme),
            let scheme = ServerAddress.Scheme(rawValue: schemeRaw)
        else {
            return nil
        }
        return ServerAddress(scheme: scheme, host: host, port: defaults.integer(forKey: keys.port))
    }

    /// A `nil` address clears all three keys, so removing the local address can't leave a stale
    /// host behind for the next load to resurrect.
    private func write(_ address: ServerAddress?, to keys: Keys.Address) {
        guard let address else {
            for key in [keys.scheme, keys.host, keys.port] { defaults.removeObject(forKey: key) }
            return
        }
        defaults.set(address.scheme.rawValue, forKey: keys.scheme)
        defaults.set(address.host, forKey: keys.host)
        defaults.set(address.port, forKey: keys.port)
    }

    private func write(_ value: String?, toDefaultsKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

/// A reference type so every copy of the repository value shares the one observer set, per
/// observable preference.
private final class PreferenceObservers<Value: Sendable>: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Value>.Continuation]>([:])

    /// Seeding and registration happen under the one lock that `yield` also takes, so a
    /// concurrent save is either visible to the seed read or delivered to the registered
    /// continuation — never lost between the two.
    func register(
        _ continuation: AsyncStream<Value>.Continuation,
        seededWith currentValue: () -> Value
    ) -> UUID {
        let id = UUID()
        continuations.withLock {
            continuation.yield(currentValue())
            $0[id] = continuation
        }
        return id
    }

    func remove(_ id: UUID) {
        continuations.withLock { _ = $0.removeValue(forKey: id) }
    }

    func yield(_ value: Value) {
        let active = continuations.withLock { Array($0.values) }
        for continuation in active {
            continuation.yield(value)
        }
    }
}

private enum Keys {
    struct Address {
        let scheme: String
        let host: String
        let port: String
    }

    static let remote = Address(
        scheme: "connection.scheme", host: "connection.host", port: "connection.port"
    )
    static let local = Address(
        scheme: "connection.local.scheme", host: "connection.local.host", port: "connection.local.port"
    )
    static let username = "connection.username"
    static let password = "connection.password"
    static let theme = "theme"
    static let cameraOrder = "cameraOrder"
    static let dynamicCameraOrder = "dynamicCameraOrder"
}
