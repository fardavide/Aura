import Foundation

import CommonFrigate
import CommonNetwork
import TimelineDomain

/// Assembles one window's day timeline from review markers, motion activity, and recording gaps,
/// fetched concurrently. Each overlay is **best-effort**: a single missing or failing endpoint
/// degrades to empty rather than failing the read — the camera grid must still load even if an
/// activity endpoint is unavailable. All three failing together, though, is a server that isn't
/// answering, and is thrown so a window-by-window walk stops instead of piling more queries on it.
public struct FrigateCameraDayTimelineRepository: CameraDayTimelineRepository {
    private let config: ServerConfig
    private let api: FrigateApiClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        api = FrigateApiClient(config: config, httpClient: httpClient)
    }

    public func dayTimeline(
        for scope: TimelineScope,
        in range: TimeRange,
        bucket: TimeInterval
    ) async throws(TimelineError) -> DayTimeline {
        let base = config.baseUrl
        let cameras = scope.cameraNames.map(\.value)
        let after = range.start.timeIntervalSince1970
        let before = Swift.min(range.end.timeIntervalSince1970, Date().timeIntervalSince1970)
        let scale = Int(bucket)

        async let markers = fetch(
            FrigateReviewUrl.review(base: base, cameras: cameras, after: after, before: before, limit: reviewMarkerLimit),
            as: ReviewMarkerDto.self
        )
        async let motion = fetch(
            FrigateReviewUrl.motionActivity(base: base, cameras: cameras, after: after, before: before, scale: scale),
            as: MotionActivityDto.self
        )
        async let gaps = fetch(
            FrigateReviewUrl.recordingsUnavailable(base: base, cameras: cameras, after: after, before: before, scale: scale),
            as: RecordingGapDto.self
        )

        let (markerDtos, motionDtos, gapDtos) = await (markers, motion, gaps)
        if markerDtos == nil, motionDtos == nil, gapDtos == nil {
            throw TimelineError.unreachable
        }
        return DayTimeline(
            markers: (markerDtos ?? []).toMarkers(),
            motion: (motionDtos ?? []).toBuckets(),
            gaps: (gapDtos ?? []).toGaps()
        )
    }

    /// Best-effort GET + decode of a JSON array. Failure is `nil` — distinct from a served empty
    /// array, so the caller can tell "no data" from "no answer".
    private func fetch<Element: Decodable>(_ url: URL, as element: Element.Type) async -> [Element]? {
        guard
            let data = try? await api.get(url),
            let decoded = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return nil
        }
        return decoded
    }
}

/// Caps each window's review payload — a day of an event-dense deployment can still run to
/// hundreds of items, and the markers only gate the strip, not the screen. Server-side ordering
/// (alerts before detections, newest first within each) means truncation drops the oldest
/// detections; overall density still shows through the motion strip.
private let reviewMarkerLimit = 1000
