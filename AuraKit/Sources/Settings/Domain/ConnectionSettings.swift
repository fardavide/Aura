/// The Frigate connection the user configures. Pure domain — the Data layer persists it
/// and the composition root maps it to the infra `ServerConfig`.
public struct ConnectionSettings: Equatable, Sendable {
    public enum Scheme: String, Sendable, CaseIterable {
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
}
