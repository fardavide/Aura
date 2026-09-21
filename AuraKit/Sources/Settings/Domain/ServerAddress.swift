/// One way of reaching the Frigate server — a scheme, a host and a port. The same server can be
/// reachable at two of these (a LAN address at home, a Tailscale/DDNS address anywhere else), so
/// the address is its own value and the credentials live on `ConnectionSettings` beside it.
public struct ServerAddress: Equatable, Sendable {
    public enum Scheme: String, Sendable, CaseIterable {
        case http
        case https
    }

    public let scheme: Scheme
    public let host: String
    public let port: Int

    public init(scheme: Scheme, host: String, port: Int) {
        self.scheme = scheme
        self.host = host
        self.port = port
    }
}
