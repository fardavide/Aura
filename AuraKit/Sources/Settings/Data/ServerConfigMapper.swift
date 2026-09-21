import CommonFrigate
import SettingsDomain

public extension ServerConfig {

    /// Maps the resolved domain address onto the infra config every Frigate read is built from.
    /// Lives here rather than in the composition root because the reachability probe needs the
    /// same mapping, and two hand-written copies of it would be one too many.
    init(_ server: ActiveServer) {
        let scheme: Scheme = switch server.address.scheme {
        case .http: .http
        case .https: .https
        }
        self.init(
            scheme: scheme,
            host: server.address.host,
            port: server.address.port,
            username: server.username,
            password: server.password
        )
    }
}
