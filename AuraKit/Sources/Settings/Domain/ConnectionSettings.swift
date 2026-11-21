/// The Frigate connection the user configures. Pure domain — the Data layer persists it
/// and the composition root maps the resolved address to the infra `ServerConfig`.
///
/// One server, reachable from a local address, a remote address, or both. The addresses share
/// credentials because they reach the same Frigate instance.
public struct ConnectionSettings: Equatable, Sendable {
    public enum Addresses: Equatable, Sendable {
        case local(ServerAddress)
        case remote(ServerAddress)
        case both(local: ServerAddress, remote: ServerAddress)

        public init?(local: ServerAddress?, remote: ServerAddress?) {
            switch (local, remote) {
            case let (local?, remote?): self = .both(local: local, remote: remote)
            case (let local?, nil): self = .local(local)
            case (nil, let remote?): self = .remote(remote)
            case (nil, nil): return nil
            }
        }
    }

    public let addresses: Addresses
    /// Empty live settings retain the Frigate proxy used by older installations. Direct live
    /// playback reuses this route's host without inheriting Frigate credentials.
    public let remoteLive: LiveConnectionSettings?
    public let localLive: LiveConnectionSettings?
    public let username: String?
    public let password: String?

    public init(
        addresses: Addresses,
        remoteLive: LiveConnectionSettings?,
        localLive: LiveConnectionSettings?,
        username: String?,
        password: String?
    ) {
        self.addresses = addresses
        self.remoteLive = remoteLive
        self.localLive = localLive
        self.username = username
        self.password = password
    }

    public init(
        remote: ServerAddress,
        local: ServerAddress?,
        remoteLive: LiveConnectionSettings?,
        localLive: LiveConnectionSettings?,
        username: String?,
        password: String?
    ) {
        self.init(
            addresses: local.map { .both(local: $0, remote: remote) } ?? .remote(remote),
            remoteLive: remoteLive,
            localLive: localLive,
            username: username,
            password: password
        )
    }

    public var remote: ServerAddress? {
        switch addresses {
        case .remote(let remote), .both(_, let remote): remote
        case .local: nil
        }
    }

    public var local: ServerAddress? {
        switch addresses {
        case .local(let local), .both(let local, _): local
        case .remote: nil
        }
    }

    public var remoteServer: ActiveServer? {
        remote.map { activeServer(route: .remote, address: $0) }
    }

    public var localServer: ActiveServer? {
        local.map { activeServer(route: .local, address: $0) }
    }

    /// The address to use when there is no successful local probe.
    public var fallbackServer: ActiveServer {
        switch addresses {
        case .local(let local): activeServer(route: .local, address: local)
        case .remote(let remote), .both(_, let remote): activeServer(route: .remote, address: remote)
        }
    }

    private func activeServer(route: ServerRoute, address: ServerAddress) -> ActiveServer {
        ActiveServer(
            route: route,
            address: address,
            live: route == .local ? localLive : remoteLive,
            username: username,
            password: password
        )
    }
}
