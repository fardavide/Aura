/// The Frigate connection the user configures. Pure domain — the Data layer persists it
/// and the composition root maps the resolved address to the infra `ServerConfig`.
///
/// One server, up to two ways in. `remote` is the address that works from anywhere and is the
/// only required one; `local` is an optional home-network address preferred whenever it answers.
/// Both carry the same credentials, because both reach the same Frigate.
public struct ConnectionSettings: Equatable, Sendable {
    public let remote: ServerAddress
    /// `nil` when no home-network address is configured — the app then always uses `remote` and
    /// never probes, which is the shape every install had before this existed.
    public let local: ServerAddress?
    public let username: String?
    public let password: String?

    public init(remote: ServerAddress, local: ServerAddress?, username: String?, password: String?) {
        self.remote = remote
        self.local = local
        self.username = username
        self.password = password
    }

    public var remoteServer: ActiveServer {
        ActiveServer(route: .remote, address: remote, username: username, password: password)
    }

    /// `nil` exactly when no local address is configured.
    public var localServer: ActiveServer? {
        local.map { ActiveServer(route: .local, address: $0, username: username, password: password) }
    }
}
