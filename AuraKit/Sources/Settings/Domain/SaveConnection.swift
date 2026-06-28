import Foundation

/// Validates and persists the Frigate connection settings.
public struct SaveConnection: Sendable {
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository) {
        self.repository = repository
    }

    public func execute(_ settings: ConnectionSettings) throws(SettingsError) {
        let host = settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw .invalidHost }
        guard (1...65_535).contains(settings.port) else { throw .invalidPort }
        repository.saveConnection(
            ConnectionSettings(
                scheme: settings.scheme,
                host: host,
                port: settings.port,
                username: settings.username,
                password: settings.password
            )
        )
    }
}
