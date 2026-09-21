import Foundation

/// Validates and persists the Frigate connection settings. Both addresses are held to the same
/// rules — an unusable local address would silently cost every launch at home a failed probe.
public struct SaveConnection: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute(_ settings: ConnectionSettings) throws(SettingsError) {
        let remote = try validated(settings.remote, on: .remote)
        let local: ServerAddress?
        if let configured = settings.local {
            local = try validated(configured, on: .local)
        } else {
            local = nil
        }
        repository.saveConnection(
            ConnectionSettings(
                remote: remote,
                local: local,
                username: settings.username,
                password: settings.password
            )
        )
    }

    private func validated(_ address: ServerAddress, on route: ServerRoute) throws(SettingsError) -> ServerAddress {
        let host = address.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw .invalidHost(route) }
        guard (1...65_535).contains(address.port) else { throw .invalidPort(route) }
        return ServerAddress(scheme: address.scheme, host: host, port: address.port)
    }
}
