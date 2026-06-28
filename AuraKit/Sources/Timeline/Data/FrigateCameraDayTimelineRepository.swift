import Foundation

import CommonFrigate
import CommonNetwork
import TimelineDomain

/// Assembles the day timeline from review markers, motion activity, and recording gaps, fetched
/// concurrently. Each overlay is **best-effort**: a missing or failing endpoint degrades to empty
/// rather than failing the whole screen — connectivity and auth are already proven by the grid, so
/// the camera scrub-grid must still load even if an activity endpoint is unavailable.
public struct FrigateCameraDayTimelineRepository: CameraDayTimelineRepository {
    private let config: ServerConfig
    private let httpClient: any HttpClient

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
    }

    public func dayTimeline(in range: TimeRange) async throws(TimelineError) -> DayTimeline {
        let base = config.baseUrl
        let after = range.start.timeIntervalSince1970
        let before = Swift.min(range.end.timeIntervalSince1970, Date().timeIntervalSince1970)
        // Coarser buckets for wider spans so the motion strip stays light (~2000 points max).
        let scale = Swift.max(60, Int((before - after) / 2000))

        async let markers = fetch(FrigateReviewUrl.review(base: base, after: after, before: before), as: ReviewMarkerDto.self)
        async let motion = fetch(FrigateReviewUrl.motionActivity(base: base, after: after, before: before, scale: scale), as: MotionActivityDto.self)
        async let gaps = fetch(FrigateReviewUrl.recordingsUnavailable(base: base, after: after, before: before, scale: scale), as: RecordingGapDto.self)

        return DayTimeline(
            markers: await markers.toMarkers(),
            motion: await motion.toBuckets(),
            gaps: await gaps.toGaps()
        )
    }

    /// Best-effort GET + decode of a JSON array; any failure yields an empty array.
    private func fetch<Element: Decodable>(_ url: URL, as element: Element.Type) async -> [Element] {
        guard
            let data = try? await authorizedData(url: url, config: config, httpClient: httpClient),
            let decoded = try? JSONDecoder().decode([Element].self, from: data)
        else {
            return []
        }
        return decoded
    }
}
