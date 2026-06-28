import Foundation

/// What the player needs to show a camera's live feed: the stream URL plus any HTTP headers
/// (e.g. auth) to attach to the request.
public struct CameraStreamSource: Equatable, Sendable {
    public let url: URL
    public let headers: [String: String]

    public init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }
}
