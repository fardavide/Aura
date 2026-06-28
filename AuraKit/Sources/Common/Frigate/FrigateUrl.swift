import Foundation

/// Frigate JSON endpoints the client reads.
public enum FrigateEndpoint: Sendable {
    case config
    case events(limit: Int)

    public func url(base: URL) -> URL {
        switch self {
        case .config:
            makeUrl(base: base, path: "api/config")
        case .events(let limit):
            makeUrl(
                base: base,
                path: "api/events",
                queryItems: [URLQueryItem(name: "limit", value: String(limit))]
            )
        }
    }
}

/// Builders for Frigate media URLs. These take the raw camera/event id strings — the
/// Data layer unwraps its typed ids at the boundary, so this infra never imports a Domain.
public enum FrigateMediaUrl {

    /// The latest still for a camera (grid tiles).
    public static func latestImage(base: URL, camera: String, height: Int) -> URL {
        makeUrl(
            base: base,
            path: "api/\(camera)/latest.jpg",
            queryItems: [URLQueryItem(name: "height", value: String(height))]
        )
    }

    /// An event's thumbnail image.
    public static func thumbnail(base: URL, eventId: String) -> URL {
        makeUrl(base: base, path: "api/events/\(eventId)/thumbnail.jpg")
    }

    /// An event's recorded clip.
    public static func clip(base: URL, eventId: String) -> URL {
        makeUrl(base: base, path: "api/events/\(eventId)/clip.mp4")
    }
}

/// The live go2rtc HLS stream, proxied through Frigate so it reuses the base URL + its auth
/// (no separate go2rtc port to expose). `src` is the go2rtc stream name.
public enum FrigateLiveUrl {
    public static func stream(base: URL, src: String) -> URL {
        makeUrl(
            base: base,
            path: "api/go2rtc/api/stream.m3u8",
            queryItems: [URLQueryItem(name: "src", value: src)]
        )
    }
}

/// Appends a path (and optional query) to a base URL. The inputs come from validated
/// config, so a nil here is an impossible state rather than a runtime failure path.
func makeUrl(base: URL, path: String, queryItems: [URLQueryItem] = []) -> URL {
    let withPath = base.appending(path: path)
    guard !queryItems.isEmpty else { return withPath }
    guard
        var components = URLComponents(url: withPath, resolvingAgainstBaseURL: false)
    else {
        preconditionFailure("Cannot decompose \(withPath)")
    }
    components.queryItems = queryItems
    guard let url = components.url else {
        preconditionFailure("Cannot build URL from \(components)")
    }
    return url
}
