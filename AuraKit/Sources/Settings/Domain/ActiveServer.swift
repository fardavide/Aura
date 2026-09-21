/// Which of the configured addresses the app is talking to.
public enum ServerRoute: String, Equatable, Sendable, CaseIterable {
    case local
    case remote
}

/// The one address every read currently goes to, with the credentials to reach it. This is what
/// the composition root hands to the Data layer — nothing below the root ever sees the second
/// address, so no repository has to know that a choice was made.
public struct ActiveServer: Equatable, Sendable {
    public let route: ServerRoute
    public let address: ServerAddress
    public let username: String?
    public let password: String?

    public init(route: ServerRoute, address: ServerAddress, username: String?, password: String?) {
        self.route = route
        self.address = address
        self.username = username
        self.password = password
    }
}
