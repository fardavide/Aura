import Foundation

/// Frigate JSON endpoints the client reads.
public enum FrigateEndpoint: Sendable {
    case config
    /// Runtime stats — the light endpoint carrying `service.storage` (disk free/total).
    case stats
    /// Events list. `after` and `before` (Unix epoch seconds) bound the window server-side — the
    /// grid's "today" summary passes the start of the day as `after`; the list view pages
    /// backwards by passing the oldest event it holds as `before` (the server's clause is
    /// `start_time < before`).
    case events(limit: Int, after: Double?, before: Double?)
    /// One event by id — the whole row, including the fields the list's projection leaves out.
    case event(id: String)
    /// The server's whole export library, newest first. Unpaged — the endpoint takes no window.
    case exports
    /// One export by id — how a clip still being cut is followed to ready.
    case export(id: String)
    /// Start cutting a clip. ⚠️ **Singular `export`, unlike the two reads above** — Frigate lists
    /// and fetches under `/api/exports` but writes under `/api/export`, and getting the number
    /// wrong 404s. Bounds are whole seconds because the handler converts them to integers anyway.
    case startExport(camera: String, start: Int, end: Int)

    public func url(base: URL) -> URL {
        switch self {
        case .config:
            makeUrl(base: base, path: "api/config")
        case .stats:
            makeUrl(base: base, path: "api/stats")
        case .events(let limit, let after, let before):
            makeUrl(
                base: base,
                path: "api/events",
                queryItems: [URLQueryItem(name: "limit", value: String(limit))]
                    + (after.map { [URLQueryItem(name: "after", value: String(Int($0.rounded())))] } ?? [])
                    // Unrounded, unlike `after`: the cursor is an event's exact start time, and
                    // rounding it to a whole second would skip (or re-serve) a busy second's events.
                    + (before.map { [URLQueryItem(name: "before", value: String($0))] } ?? [])
            )
        case .event(let id):
            makeUrl(base: base, path: "api/events/\(id)")
        case .exports:
            makeUrl(base: base, path: "api/exports")
        case .export(let id):
            makeUrl(base: base, path: "api/exports/\(id)")
        case .startExport(let camera, let start, let end):
            makeUrl(base: base, path: "api/export/\(camera)/start/\(start)/end/\(end)")
        }
    }
}

/// Resolves the server filesystem paths an export record carries (`video_path`, `thumb_path`) to
/// the URLs that serve them.
///
/// Frigate reports these as paths under `/media/frigate/`, and the media itself is served from the
/// **root** — no `api/` prefix, like `/vod/` — with that prefix stripped. Verified against the
/// v0.17.2 web UI, which builds exactly `baseUrl + video_path.replace("/media/frigate/", "")`.
public enum FrigateExportMediaUrl {
    private static let mediaRoot = "/media/frigate/"

    /// Nil for anything that is not a plain path inside the media root — the record comes from the
    /// server and is treated as untrusted input, so a path that escapes the root, or climbs with
    /// `..`, is refused here rather than resolved into a request against some other part of the
    /// host. The caller drops the export instead of offering a control that cannot work.
    public static func media(base: URL, serverPath: String) -> URL? {
        guard serverPath.hasPrefix(mediaRoot) else { return nil }
        let relative = String(serverPath.dropFirst(mediaRoot.count))
        guard !relative.isEmpty else { return nil }
        let segments = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }
        return makeUrl(base: base, path: relative)
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

    /// An event's full-frame still (the thumbnail is an object crop). Only served when the event
    /// has `has_snapshot`; `height` bounds the transfer for a card-sized image.
    public static func snapshot(base: URL, eventId: String, height: Int) -> URL {
        makeUrl(
            base: base,
            path: "api/events/\(eventId)/snapshot.jpg",
            queryItems: [URLQueryItem(name: "height", value: String(height))]
        )
    }

    /// An event's recorded clip.
    public static func clip(base: URL, eventId: String) -> URL {
        makeUrl(base: base, path: "api/events/\(eventId)/clip.mp4")
    }
}

/// The two Frigate+ submission endpoints — the verdicts a user can give a detection. Both put the
/// event's snapshot in the Frigate+ dataset; `falsePositive` additionally records that the label
/// was wrong. Neither carries the *right* label: Frigate's API has no parameter for it, so the
/// correction is made on the Frigate+ site.
public enum FrigatePlusUrl {

    /// Confirms the detection. Takes a JSON body; `{"include_annotation": 1}` uploads the bounding
    /// box with the image.
    public static func submit(base: URL, eventId: String) -> URL {
        makeUrl(base: base, path: "api/events/\(eventId)/plus")
    }

    /// Reports the detection as wrong. A **PUT**, unlike its sibling, and bodyless — it submits the
    /// event first if it isn't in the dataset yet.
    public static func falsePositive(base: URL, eventId: String) -> URL {
        makeUrl(base: base, path: "api/events/\(eventId)/false_positive")
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
