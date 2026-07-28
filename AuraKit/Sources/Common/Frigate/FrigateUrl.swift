import Foundation

/// Frigate JSON endpoints the client reads.
public enum FrigateEndpoint: Sendable {
    case config
    /// Runtime stats — the light endpoint carrying `service.storage` (disk free/total).
    case stats
    /// Events list. `after` (Unix epoch seconds) bounds the window server-side — the grid's
    /// "today" summary passes the start of the day; the list view passes nil for all events.
    case events(limit: Int, after: Double?)

    public func url(base: URL) -> URL {
        switch self {
        case .config:
            makeUrl(base: base, path: "api/config")
        case .stats:
            makeUrl(base: base, path: "api/stats")
        case .events(let limit, let after):
            makeUrl(
                base: base,
                path: "api/events",
                queryItems: [URLQueryItem(name: "limit", value: String(limit))]
                    + (after.map { [URLQueryItem(name: "after", value: String(Int($0.rounded())))] } ?? [])
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

/// Builders for the day-timeline overlays. `after`/`before` are Unix epoch seconds — the Data
/// layer converts its `Date`s at the boundary.
///
/// An **empty** `cameras` omits the param entirely, which is how the server means "all cameras".
/// The `cameras=all` sentinel is only documented for `/api/events`, so it is never sent here.
public enum FrigateReviewUrl {

    /// Activity markers (alerts + detections) in the window. `limit` is required because the
    /// server answers an unbounded query with every review item in the window — on an
    /// event-dense deployment that payload gates first paint. Frigate orders severity asc then
    /// start_time desc, so truncation keeps all alerts before the oldest detections drop.
    public static func review(base: URL, cameras: [String], after: Double, before: Double, limit: Int) -> URL {
        makeUrl(
            base: base,
            path: "api/review",
            queryItems: scope(cameras) + window(after: after, before: before)
                + [URLQueryItem(name: "limit", value: String(limit))]
        )
    }

    /// Normalized motion-intensity buckets for the activity strip.
    public static func motionActivity(base: URL, cameras: [String], after: Double, before: Double, scale: Int) -> URL {
        makeUrl(
            base: base,
            path: "api/review/activity/motion",
            queryItems: scope(cameras) + window(after: after, before: before)
                + [URLQueryItem(name: "scale", value: String(scale))]
        )
    }

    /// The spans that have no recording (drawn as gaps).
    public static func recordingsUnavailable(base: URL, cameras: [String], after: Double, before: Double, scale: Int) -> URL {
        makeUrl(
            base: base,
            path: "api/recordings/unavailable",
            queryItems: scope(cameras) + window(after: after, before: before)
                + [URLQueryItem(name: "scale", value: String(scale))]
        )
    }

    private static func scope(_ cameras: [String]) -> [URLQueryItem] {
        cameras.isEmpty ? [] : [URLQueryItem(name: "cameras", value: cameras.joined(separator: ","))]
    }

    private static func window(after: Double, before: Double) -> [URLQueryItem] {
        [
            URLQueryItem(name: "after", value: epochSeconds(after.rounded())),
            URLQueryItem(name: "before", value: epochSeconds(before.rounded())),
        ]
    }
}

/// Builders for the per-camera preview (scrub-grid) endpoints. `camera` may be `"all"`.
public enum FrigatePreviewUrl {

    /// The past-hour preview clip list. Range bounds are rounded, matching the web UI.
    public static func clipList(base: URL, camera: String, after: Double, before: Double) -> URL {
        makeUrl(base: base, path: "api/preview/\(camera)/start/\(epochSeconds(after.rounded()))/end/\(epochSeconds(before.rounded()))")
    }

    /// The current-hour preview frame list. Bounds are floored/ceiled, matching the web UI.
    public static func frameList(base: URL, camera: String, after: Double, before: Double) -> URL {
        makeUrl(base: base, path: "api/preview/\(camera)/start/\(epochSeconds(after.rounded(.down)))/end/\(epochSeconds(before.rounded(.up)))/frames")
    }

    /// One preview frame image.
    public static func frameThumbnail(base: URL, fileName: String) -> URL {
        makeUrl(base: base, path: "api/preview/\(fileName)/thumbnail.webp")
    }

    /// Resolves a clip's leading-slash `src` path to a playable URL (`<base>/<src>`).
    public static func clipMedia(base: URL, path: String) -> URL {
        makeUrl(base: base, path: String(path.drop(while: { $0 == "/" })))
    }
}

/// Builders for full-resolution recordings playback. Both take the **same** window bounds — the
/// mapping from wall clock onto player time is only correct while the segments described and the
/// stream served cover exactly the same seconds, so both floor identically.
public enum FrigateRecordingsUrl {

    /// The recording segments covering the window — the ground truth for what is playable.
    public static func segments(base: URL, camera: String, after: Double, before: Double) -> URL {
        makeUrl(
            base: base,
            path: "api/\(camera)/recordings",
            queryItems: [
                URLQueryItem(name: "after", value: epochSeconds(after.rounded(.down))),
                URLQueryItem(name: "before", value: epochSeconds(before.rounded(.down))),
            ]
        )
    }

    /// The window's HLS playlist. Served by the media module at the **root** — unlike every other
    /// endpoint here it carries no `api/` prefix, and the `api/vod/…` route answers with a JSON
    /// manifest instead of a playlist.
    public static func playlist(base: URL, camera: String, after: Double, before: Double) -> URL {
        makeUrl(
            base: base,
            path: "vod/\(camera)/start/\(epochSeconds(after.rounded(.down)))/end/\(epochSeconds(before.rounded(.down)))/master.m3u8"
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

/// Renders an epoch-seconds value as an integer string for a URL path or query (no decimals).
private func epochSeconds(_ value: Double) -> String {
    String(Int(value))
}
