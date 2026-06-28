import Foundation

import CommonFrigate
import CommonNetwork
import TimelineDomain

/// Assembles the day timeline by fetching review markers, motion activity, and recording gaps
/// concurrently from Frigate.
public struct FrigateCameraDayTimelineRepository: CameraDayTimelineRepository {
    private let config: ServerConfig
    private let httpClient: any HttpClient
    private let bucketScale = 60

    public init(config: ServerConfig, httpClient: any HttpClient) {
        self.config = config
        self.httpClient = httpClient
    }

    public func dayTimeline(in range: TimeRange) async throws(TimelineError) -> DayTimeline {
        let base = config.baseUrl
        let after = range.start.timeIntervalSince1970
        let before = range.end.timeIntervalSince1970

        async let review = get(FrigateReviewUrl.review(base: base, after: after, before: before))
        async let motion = get(FrigateReviewUrl.motionActivity(base: base, after: after, before: before, scale: bucketScale))
        async let gaps = get(FrigateReviewUrl.recordingsUnavailable(base: base, after: after, before: before, scale: bucketScale))

        // `async let` erases typed throws to `any Error`, so recover the TimelineError here.
        let reviewData: Data
        let motionData: Data
        let gapsData: Data
        do {
            reviewData = try await review
            motionData = try await motion
            gapsData = try await gaps
        } catch let error as TimelineError {
            throw error
        } catch {
            throw TimelineError.unknown
        }

        do {
            return DayTimeline(
                markers: try JSONDecoder().decode([ReviewMarkerDto].self, from: reviewData).toMarkers(),
                motion: try JSONDecoder().decode([MotionActivityDto].self, from: motionData).toBuckets(),
                gaps: try JSONDecoder().decode([RecordingGapDto].self, from: gapsData).toGaps()
            )
        } catch {
            throw TimelineError.invalidData
        }
    }

    private func get(_ url: URL) async throws(TimelineError) -> Data {
        try await authorizedData(url: url, config: config, httpClient: httpClient)
    }
}
