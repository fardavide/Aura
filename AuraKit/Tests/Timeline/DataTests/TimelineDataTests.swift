import Foundation
import Testing

import CamerasEntities
import CommonFrigate
import CommonNetwork
import TestDoubles
import TimelineDomain
@testable import TimelineData

struct TimelineDecodingTests {

    @Test func `given review json when mapping then it keeps alert and detection and drops the rest`() throws {
        let markers = try JSONDecoder().decode([ReviewMarkerDto].self, from: Data(reviewJson.utf8)).toMarkers()
        #expect(markers.map(\.severity) == [.alert, .detection])
        #expect(markers.first?.start == at(100))
        #expect(markers.first?.end == at(160))
    }

    @Test func `given an in-progress marker then its end is nil`() throws {
        let markers = try JSONDecoder().decode([ReviewMarkerDto].self, from: Data(reviewJson.utf8)).toMarkers()
        #expect(markers.last?.end == nil)
    }

    @Test func `given motion json when mapping then intensity is clamped to 0 through 100`() throws {
        let buckets = try JSONDecoder().decode([MotionActivityDto].self, from: Data(motionJson.utf8)).toBuckets()
        #expect(buckets.map(\.intensity) == [50, 100, 0])
    }

    @Test func `given frame filenames when mapping then valid ones parse their timestamp`() {
        let frames = ["preview_driveway-1700.webp", "bad-name.txt"].toFrames(camera: CameraName("driveway"))
        #expect(frames.count == 1)
        #expect(frames.first?.time == at(1700))
        #expect(frames.first?.fileName == "preview_driveway-1700.webp")
    }

    @Test func `given recordings json when mapping then bounds and encoded duration are read`() throws {
        let segments = try JSONDecoder().decode([RecordingSegmentDto].self, from: Data(recordingsJson.utf8)).toSegments()
        #expect(segments.first?.range == TimeRange(start: at(100), end: at(110)))
        #expect(segments.first?.duration == 10)
    }

    // The encoded file can be shorter than the span it covers; playback follows the file, so the
    // reported duration must survive mapping rather than being recomputed from the bounds.
    @Test func `given a duration that disagrees with the span when mapping then the reported duration is kept`() throws {
        let segments = try JSONDecoder().decode([RecordingSegmentDto].self, from: Data(recordingsJson.utf8)).toSegments()
        #expect(segments.last?.range == TimeRange(start: at(110), end: at(120)))
        #expect(segments.last?.duration == 9.5)
    }
}

struct FrigateCameraRecordingsRepositoryTests {

    @Test func `given segments json when fetching then they map to domain segments`() async throws {
        // given
        let sut = FrigateCameraRecordingsRepository(
            config: .test, httpClient: FakeHttpClient(.response(status: 200, body: Data(recordingsJson.utf8)))
        )

        // when
        let segments = try await sut.segments(for: CameraName("driveway"), in: window)

        // then
        #expect(segments.count == 2)
        #expect(segments.first?.duration == 10)
    }

    @Test func `when fetching segments then the camera recordings endpoint is queried for the window`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data(recordingsJson.utf8)))
        let sut = FrigateCameraRecordingsRepository(config: .test, httpClient: http)

        // when
        _ = try await sut.segments(for: CameraName("driveway"), in: TimeRange(start: at(3600), end: at(7200)))

        // then
        #expect(
            http.lastRequest?.url
                == URL(string: "http://frigate.test:5000/api/driveway/recordings?after=3600&before=7200")!
        )
    }

    @Test func `given malformed json when fetching segments then it throws invalid data`() async {
        let sut = FrigateCameraRecordingsRepository(
            config: .test, httpClient: FakeHttpClient(.response(status: 200, body: Data("nonsense".utf8)))
        )
        await #expect(throws: TimelineError.invalidData) { try await sut.segments(for: CameraName("driveway"), in: window) }
    }

    @Test func `given an unauthorized server when fetching segments then it throws not authorized`() async {
        let sut = FrigateCameraRecordingsRepository(
            config: .test, httpClient: FakeHttpClient(.response(status: 401, body: Data()))
        )
        await #expect(throws: TimelineError.notAuthorized) { try await sut.segments(for: CameraName("driveway"), in: window) }
    }

    // The playlist has to cover exactly the window the segments described, or every mapped
    // instant lands somewhere else in the stream.
    @Test func `when resolving the playback source then it points at the same window's playlist`() {
        // given
        let sut = FrigateCameraRecordingsRepository(
            config: .test, httpClient: FakeHttpClient(.response(status: 200, body: Data()))
        )

        // when
        let source = sut.playbackSource(for: CameraName("driveway"), in: TimeRange(start: at(3600), end: at(7200)))

        // then
        #expect(source.url == URL(string: "http://frigate.test:5000/vod/driveway/start/3600/end/7200/master.m3u8")!)
    }

    @Test func `given credentials when resolving the playback source then it carries the auth header`() {
        let sut = FrigateCameraRecordingsRepository(
            config: .authed, httpClient: FakeHttpClient(.response(status: 200, body: Data()))
        )
        #expect(sut.playbackSource(for: CameraName("driveway"), in: window).headers["Authorization"] != nil)
    }
}

struct FrigateCameraDayTimelineRepositoryTests {

    @Test func `given the timeline endpoints when fetching the day then it assembles overlays`() async throws {
        let sut = FrigateCameraDayTimelineRepository(config: .test, httpClient: FakeHttpClient(routes: [
            ("review/activity/motion", .response(status: 200, body: Data(motionJson.utf8))),
            ("recordings/unavailable", .response(status: 200, body: Data(gapsJson.utf8))),
            ("api/review", .response(status: 200, body: Data(reviewJson.utf8))),
        ]))

        let timeline = try await sut.dayTimeline(for: .allCameras, in: window, bucket: 300)

        #expect(timeline.markers.count == 2)
        #expect(timeline.motion.count == 3)
        #expect(timeline.gaps.count == 1)
    }

    @Test func `when fetching the day then the bucket is sent as the scale on motion and gaps`() async throws {
        // given
        let http = FakeHttpClient(.response(status: 200, body: Data("[]".utf8)))
        let sut = FrigateCameraDayTimelineRepository(config: .test, httpClient: http)

        // when
        _ = try await sut.dayTimeline(for: .allCameras, in: window, bucket: 302)

        // then — whole seconds on the wire, on both scaled queries
        #expect(http.requestedUrls.contains { $0.contains("activity/motion") && $0.hasSuffix("scale=302") })
        #expect(http.requestedUrls.contains { $0.contains("recordings/unavailable") && $0.hasSuffix("scale=302") })
    }

    // The review body is served only to a capped query; an uncapped one falls through to the
    // motion body, which decodes no markers — so the assertion pins the limit without racing
    // the three concurrent fetches for a single lastRequest.
    @Test func `when fetching the day then the review query is capped`() async throws {
        let sut = FrigateCameraDayTimelineRepository(config: .test, httpClient: FakeHttpClient(routes: [
            ("review/activity/motion", .response(status: 200, body: Data(motionJson.utf8))),
            ("recordings/unavailable", .response(status: 200, body: Data(gapsJson.utf8))),
            ("limit=1000", .response(status: 200, body: Data(reviewJson.utf8))),
        ]))

        let timeline = try await sut.dayTimeline(for: .allCameras, in: window, bucket: 300)

        #expect(timeline.markers.count == 2)
    }

    // The review body is served only to a camera-scoped query; an unscoped one falls through to the
    // motion body, which decodes no markers — so the assertion pins the scope without racing the
    // three concurrent fetches for a single lastRequest.
    @Test func `given one camera when fetching the day then every overlay query is scoped to it`() async throws {
        let sut = FrigateCameraDayTimelineRepository(config: .test, httpClient: FakeHttpClient(routes: [
            ("activity/motion?cameras=driveway", .response(status: 200, body: Data(motionJson.utf8))),
            ("unavailable?cameras=driveway", .response(status: 200, body: Data(gapsJson.utf8))),
            ("api/review?cameras=driveway", .response(status: 200, body: Data(reviewJson.utf8))),
        ]))

        let timeline = try await sut.dayTimeline(for: .camera(CameraName("driveway")), in: window, bucket: 300)

        #expect(timeline.markers.count == 2)
        #expect(timeline.motion.count == 3)
        #expect(timeline.gaps.count == 1)
    }

    @Test func `given a failing overlay endpoint when fetching the day then that overlay degrades to empty`() async throws {
        let sut = FrigateCameraDayTimelineRepository(config: .test, httpClient: FakeHttpClient(routes: [
            ("review/activity/motion", .response(status: 200, body: Data(motionJson.utf8))),
            ("recordings/unavailable", .response(status: 500, body: Data())),
            ("api/review", .response(status: 200, body: Data(reviewJson.utf8))),
        ]))

        let timeline = try await sut.dayTimeline(for: .allCameras, in: window, bucket: 300)

        #expect(timeline.markers.count == 2)
        #expect(timeline.motion.count == 3)
        #expect(timeline.gaps.isEmpty)
    }

    // One endpoint down degrades; all three down is a server that isn't answering, and the
    // window-by-window walk must stop asking it for more days.
    @Test func `given every overlay endpoint failing when fetching the day then it throws unreachable`() async {
        let sut = FrigateCameraDayTimelineRepository(
            config: .test, httpClient: FakeHttpClient(.response(status: 500, body: Data()))
        )
        await #expect(throws: TimelineError.unreachable) {
            _ = try await sut.dayTimeline(for: .allCameras, in: window, bucket: 300)
        }
    }
}

struct FrigatePreviewSourceProviderTests {

    @Test func `given a clip list when fetching clips then they decode`() async throws {
        let sut = FrigatePreviewSourceProvider(
            config: .test, httpClient: FakeHttpClient(.response(status: 200, body: Data(clipsJson.utf8)))
        )
        let clips = try await sut.clips(for: CameraName("driveway"), in: window)
        #expect(clips.count == 1)
        #expect(clips.first?.path == "/clips/previews/driveway-1.mp4")
        #expect(clips.first?.range.start == at(100))
    }

    @Test func `given a frame list when fetching frames then filenames parse`() async throws {
        let sut = FrigatePreviewSourceProvider(
            config: .test, httpClient: FakeHttpClient(.response(status: 200, body: Data(framesJson.utf8)))
        )
        let frames = try await sut.frames(for: CameraName("driveway"), in: window)
        #expect(frames.first?.time == at(1700))
    }

    @Test func `given credentials when resolving a clip source then it carries the auth header`() {
        let sut = FrigatePreviewSourceProvider(
            config: .authed, httpClient: FakeHttpClient(.response(status: 200, body: Data()))
        )
        let clip = PreviewClip(camera: CameraName("driveway"), range: window, path: "/clips/previews/driveway-1.mp4")
        let source = sut.clipSource(clip)
        #expect(source.url == URL(string: "http://frigate.test:5000/clips/previews/driveway-1.mp4")!)
        #expect(source.headers["Authorization"] != nil)
    }

    @Test func `given a non-success status when fetching clips then it throws`() async {
        let sut = FrigatePreviewSourceProvider(
            config: .test, httpClient: FakeHttpClient(.response(status: 404, body: Data()))
        )
        await #expect(throws: TimelineError.unknown) { try await sut.clips(for: CameraName("driveway"), in: window) }
    }
}

struct FrigatePreviewImageLoaderTests {

    @Test func `given a 200 when loading a frame then it returns bytes`() async {
        let bytes = Data([0x01, 0x02])
        let sut = FrigatePreviewImageLoader(config: .test, httpClient: FakeHttpClient(.response(status: 200, body: bytes)))
        #expect(await sut.frameImage(frame) == bytes)
    }

    @Test func `given a 404 when loading a frame then it is nil`() async {
        let sut = FrigatePreviewImageLoader(config: .test, httpClient: FakeHttpClient(.response(status: 404, body: Data())))
        #expect(await sut.frameImage(frame) == nil)
    }
}

// MARK: - Fixtures

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
private let window = TimeRange(start: at(0), end: at(86_400))
private let frame = PreviewFrame(camera: CameraName("driveway"), time: at(1700), fileName: "preview_driveway-1700.webp")

private let reviewJson = """
[
  { "id": "r1", "camera": "driveway", "start_time": 100.0, "end_time": 160.0, "severity": "alert" },
  { "id": "r2", "camera": "yard", "start_time": 200.0, "end_time": 260.0, "severity": "significant_motion" },
  { "id": "r3", "camera": "garage", "start_time": 300.0, "end_time": null, "severity": "detection" }
]
"""

private let motionJson = """
[
  { "start_time": 100, "motion": 50.0, "camera": "all" },
  { "start_time": 160, "motion": 120.0, "camera": "all" },
  { "start_time": 220, "motion": -5.0, "camera": "all" }
]
"""

private let gapsJson = #"[ { "start_time": 500, "end_time": 600 } ]"#

private let clipsJson = """
[ { "camera": "driveway", "src": "/clips/previews/driveway-1.mp4", "type": "video/mp4", "start": 100.0, "end": 700.0 } ]
"""

private let framesJson = #"[ "preview_driveway-1700.webp", "preview_driveway-1710.webp" ]"#

private let recordingsJson = """
[
  { "id": "s1", "start_time": 100.0, "end_time": 110.0, "duration": 10.0, "motion": 4, "objects": 0, "segment_size": 1.2 },
  { "id": "s2", "start_time": 110.0, "end_time": 120.0, "duration": 9.5, "motion": 0, "objects": 0, "segment_size": 1.1 }
]
"""

extension ServerConfig {
    static let test = ServerConfig(scheme: .http, host: "frigate.test", port: 5000, username: nil, password: nil)
    static let authed = ServerConfig(scheme: .http, host: "frigate.test", port: 5000, username: "u", password: "p")
}
