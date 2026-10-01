/// Live playback reaches the selected Frigate address's host with its own scheme and port.
/// An absent value uses the Frigate live proxy.
public struct LiveConnectionSettings: Equatable, Sendable {
    public let scheme: ServerAddress.Scheme
    public let port: Int

    public init(scheme: ServerAddress.Scheme, port: Int) {
        self.scheme = scheme
        self.port = port
    }
}
