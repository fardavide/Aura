import Foundation
import Observation

import SettingsDomain

@Observable
@MainActor
public final class ServerSettingsViewModel {
    public var remoteScheme: ServerAddress.Scheme = .http
    public var remoteHost: String = ""
    public var remotePort: String = "5000"
    /// An empty host is how the form says "no local address" — the fields stay on screen so
    /// adding one later is typing, not a hunt for a hidden control.
    public var localScheme: ServerAddress.Scheme = .http
    public var localHost: String = ""
    public var localPort: String = "5000"
    public var username: String = ""
    public var password: String = ""

    public private(set) var errorMessage: String?
    public private(set) var didSave = false

    private let loadConnection: LoadConnection
    private let saveConnection: SaveConnection

    public init(loadConnection: LoadConnection, saveConnection: SaveConnection) {
        self.loadConnection = loadConnection
        self.saveConnection = saveConnection
    }

    public func onAppear() {
        guard let connection = loadConnection.execute() else { return }
        remoteScheme = connection.remote.scheme
        remoteHost = connection.remote.host
        remotePort = String(connection.remote.port)
        if let local = connection.local {
            localScheme = local.scheme
            localHost = local.host
            localPort = String(local.port)
        }
        username = connection.username ?? ""
        password = connection.password ?? ""
    }

    public func save() {
        errorMessage = nil
        didSave = false
        guard let remotePortValue = Int(remotePort) else {
            errorMessage = message(for: .invalidPort(.remote))
            return
        }
        let local: ServerAddress?
        if localHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            local = nil
        } else {
            guard let localPortValue = Int(localPort) else {
                errorMessage = message(for: .invalidPort(.local))
                return
            }
            local = ServerAddress(scheme: localScheme, host: localHost, port: localPortValue)
        }
        let settings = ConnectionSettings(
            remote: ServerAddress(scheme: remoteScheme, host: remoteHost, port: remotePortValue),
            local: local,
            username: username.isEmpty ? nil : username,
            password: password.isEmpty ? nil : password
        )
        do {
            try saveConnection.execute(settings)
            didSave = true
        } catch {
            errorMessage = message(for: error)
        }
    }

    private func message(for error: SettingsError) -> String {
        switch error {
        case .invalidHost(.remote): "Enter a valid remote host."
        case .invalidHost(.local): "Enter a valid local host, or clear it to always use the remote address."
        case .invalidPort(.remote): "The remote port must be a number between 1 and 65535."
        case .invalidPort(.local): "The local port must be a number between 1 and 65535."
        // Saving a connection cannot fail this way; the icon picker reports its own failures.
        case .iconChangeFailed: "Something went wrong. Try again."
        }
    }
}
