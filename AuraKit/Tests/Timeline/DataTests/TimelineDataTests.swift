import Foundation
import Testing

import CamerasDomain
import CommonFrigate
import CommonNetwork
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
}

struct FrigateCameraDayTimelineRepositoryTests {

    @Test func `given the timeline endpoints when fetching the day then it assembles overlays`() async throws {
        let sut = FrigateCameraDayTimelineRepository(config: .test, httpClient: PathRoutingHttpClient([
            ("review/activity/motion", 200, Data(motionJson.utf8)),
            ("recordings/unavailable", 200, Data(gapsJson.utf8)),
            ("api/review", 200, Data(reviewJson.utf8)),
        ]))

        let timeline = try await sut.dayTimeline(in: window)

        #expect(timeline.markers.count == 2)
        #expect(timeline.motion.count == 3)
        #expect(timeline.gaps.count == 1)
    }

    @Test func `given a failing overlay endpoint when fetching the day then that overlay degrades to empty`() async throws {
        let sut = FrigateCameraDayTimelineRepository(config: .test, httpClient: PathRoutingHttpClient([
            ("review/activity/motion", 200, Data(motionJson.utf8)),
            ("recordings/unavailable", 500, Data()),
            ("api/review", 200, Data(reviewJson.utf8)),
        ]))

        let timeline = try await sut.dayTimeline(in: window)

        #expect(timeline.markers.count == 2)
        #expect(timeline.motion.count == 3)
        #expect(timeline.gaps.isEmpty)
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

extension ServerConfig {
    static let test = ServerConfig(scheme: .http, host: "frigate.test", port: 5000, username: nil, password: nil)
    static let authed = ServerConfig(scheme: .http, host: "frigate.test", port: 5000, username: "u", password: "p")
}

final class FakeHttpClient: HttpClient, @unchecked Sendable {
    enum Outcome {
        case response(status: Int, body: Data)
        case failure(any Error)
    }

    private let outcome: Outcome

    init(_ outcome: Outcome) { self.outcome = outcome }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        switch outcome {
        case let .response(status, body):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "http://frigate.test")!,
                statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (body, response)
        case let .failure(error):
            throw error
        }
    }
}

/// Routes by URL substring so the multi-endpoint day fetch can return a different body per path.
final class PathRoutingHttpClient: HttpClient, @unchecked Sendable {
    private let routes: [(match: String, status: Int, body: Data)]

    init(_ routes: [(String, Int, Data)]) {
        self.routes = routes.map { (match: $0.0, status: $0.1, body: $0.2) }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let urlString = request.url?.absoluteString ?? ""
        let route = routes.first { urlString.contains($0.match) } ?? routes[0]
        let response = HTTPURLResponse(url: request.url!, statusCode: route.status, httpVersion: nil, headerFields: nil)!
        return (route.body, response)
    }
}
