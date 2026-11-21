import Foundation
import Observation

import SettingsDomain

@Observable
@MainActor
public final class ServerSettingsViewModel {
    public var localAddress = ""
    public var remoteAddress = ""
    public var remoteLiveScheme: ServerAddress.Scheme = .http
    public var remoteLivePort: String = "1984"
    public var localLiveScheme: ServerAddress.Scheme = .http
    public var localLivePort: String = "1984"
    public var username: String = ""
    public var password: String = ""

    private(set) var saveError: SettingsError?
    public var errorMessage: String? { saveError.map(message(for:)) }
    public private(set) var didSave = false

    private let loadConnection: LoadConnection
    private let saveConnection: SaveConnection

    public init(loadConnection: LoadConnection, saveConnection: SaveConnection) {
        self.loadConnection = loadConnection
        self.saveConnection = saveConnection
    }

    public func onAppear() {
        guard let connection = loadConnection.execute() else { return }
        localAddress = addressText(connection.local)
        remoteAddress = addressText(connection.remote)
        localLiveScheme = connection.localLive?.scheme ?? .http
        remoteLiveScheme = connection.remoteLive?.scheme ?? .http
        localLivePort = connection.localLive.map { String($0.port) } ?? (connection.local == nil ? "1984" : "")
        remoteLivePort = connection.remoteLive.map { String($0.port) } ?? (connection.remote == nil ? "1984" : "")
        username = connection.username ?? ""
        password = connection.password ?? ""
    }

    public func save() {
        saveError = nil
        didSave = false
        do throws(SettingsError) {
            let local = try parseAddress(localAddress, route: .local)
            let remote = try parseAddress(remoteAddress, route: .remote)
            guard let addresses = ConnectionSettings.Addresses(local: local, remote: remote) else {
                throw .missingAddress
            }
            let settings = ConnectionSettings(
                addresses: addresses,
                remoteLive: remote == nil ? nil : try liveSettings(
                    scheme: remoteLiveScheme, port: remoteLivePort, route: .remote
                ),
                localLive: local == nil ? nil : try liveSettings(
                    scheme: localLiveScheme, port: localLivePort, route: .local
                ),
                username: username.isEmpty ? nil : username,
                password: password.isEmpty ? nil : password
            )
            try saveConnection.execute(settings)
            didSave = true
        } catch {
            saveError = error
        }
    }

    private func addressText(_ address: ServerAddress?) -> String {
        guard let address else { return "" }
        return "\(address.scheme.rawValue)://\(address.host):\(address.port)"
    }

    private func parseAddress(_ input: String, route: ServerRoute) throws(SettingsError) -> ServerAddress? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let hasScheme = text.contains("://")
        guard
            let components = URLComponents(string: hasScheme ? text : "http://\(text)"),
            let schemeName = components.scheme?.lowercased(),
            let scheme = ServerAddress.Scheme(rawValue: schemeName),
            let host = components.host, !host.isEmpty,
            components.user == nil, components.password == nil,
            components.path.isEmpty || components.path == "/",
            components.query == nil, components.fragment == nil,
            components.url != nil
        else { throw .invalidHost(route) }
        // Bare hosts keep the original setup port. An explicit URL uses its scheme's default.
        let defaultPort = if !hasScheme { 5000 } else { scheme == .https ? 443 : 80 }
        return ServerAddress(scheme: scheme, host: host, port: components.port ?? defaultPort)
    }

    private func liveSettings(
        scheme: ServerAddress.Scheme,
        port: String,
        route: ServerRoute
    ) throws(SettingsError) -> LiveConnectionSettings? {
        let port = port.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !port.isEmpty else { return nil }
        guard let portValue = Int(port) else { throw .invalidLivePort(route) }
        return LiveConnectionSettings(scheme: scheme, port: portValue)
    }

    private func message(for error: SettingsError) -> String {
        switch error {
        case .missingAddress: "Enter a local or remote address."
        case .invalidHost(.remote): "Enter a valid remote address."
        case .invalidHost(.local): "Enter a valid local address."
        case .invalidPort(.remote): "The remote port must be a number between 1 and 65535."
        case .invalidPort(.local): "The local port must be a number between 1 and 65535."
        case .invalidLivePort(.remote): "The remote live stream port must be a number between 1 and 65535."
        case .invalidLivePort(.local): "The local live stream port must be a number between 1 and 65535."
        case .localLiveRequiresLocalAddress: "Enter a local server address before adding a local live port."
        case .remoteLiveRequiresRemoteAddress: "Enter a remote server address before adding a remote live port."
        // Saving a connection cannot fail this way; the icon picker reports its own failures.
        case .iconChangeFailed: "Something went wrong. Try again."
        }
    }
}
