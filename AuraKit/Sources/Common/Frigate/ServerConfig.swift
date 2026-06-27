import Foundation

/// How to reach the Frigate server. The only persisted connection state (Settings owns
/// editing/persisting it); the Data layer reads it to build requests.
public struct ServerConfig: Equatable, Sendable {
    public enum Scheme: String, Sendable {
        case http
        case https
    }

    public let scheme: Scheme
    public let host: String
    public let port: Int
    public let username: String?
    public let password: String?

    public init(scheme: Scheme, host: String, port: Int, username: String?, password: String?) {
        self.scheme = scheme
        self.host = host
        self.port = port
        self.username = username
        self.password = password
    }

    /// The server's root URL. `host`/`port` are validated where the config is created
    /// (Settings), so an unbuildable URL here is a programmer error, not a runtime path.
    public var baseUrl: URL {
        var components = URLComponents()
        components.scheme = scheme.rawValue
        components.host = host
        components.port = port
        guard let url = components.url else {
            preconditionFailure("Invalid server config: \(scheme.rawValue)://\(host):\(port)")
        }
        return url
    }
}
