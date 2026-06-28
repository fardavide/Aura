import Foundation
import Testing

import CamerasDomain
@testable import TimelineDomain

struct TimeRangeTests {

    @Test func `given a time inside the window then it is contained`() {
        #expect(TimeRange(start: at(0), end: at(100)).contains(at(50)))
    }

    @Test func `given the end instant then it is not contained`() {
        #expect(!TimeRange(start: at(0), end: at(100)).contains(at(100)))
    }

    @Test func `given a time outside the window when clamping then it is pinned to the edge`() {
        let range = TimeRange(start: at(10), end: at(20))
        #expect(range.clamp(at(5)) == at(10))
        #expect(range.clamp(at(99)) == at(20))
        #expect(range.clamp(at(15)) == at(15))
    }

    @Test func `given a date when building its day then it spans start of day to next day`() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let day = TimeRange.day(containing: at(1_707_000_000), in: calendar)
        #expect(day.start == calendar.startOfDay(for: at(1_707_000_000)))
        #expect(day.end == calendar.date(byAdding: .day, value: 1, to: day.start))
        #expect(day.end.timeIntervalSince(day.start) == 86_400)
    }
}

struct PreviewClipTests {

    @Test func `given an instant within the clip then it is contained`() {
        let clip = PreviewClip(camera: CameraName("drive"), range: TimeRange(start: at(0), end: at(60)), path: "/p.mp4")
        #expect(clip.contains(at(30)))
        #expect(!clip.contains(at(60)))
    }
}

struct GetDayTimelineTests {

    @Test func `given a repository when executing then it returns the day timeline`() async throws {
        let timeline = DayTimeline(markers: [], motion: [], gaps: [])
        let sut = GetDayTimeline(repository: FakeTimelineRepository(.success(timeline)))
        #expect(try await sut.execute(in: window) == timeline)
    }

    @Test func `given a failing repository when executing then it propagates the error`() async {
        let sut = GetDayTimeline(repository: FakeTimelineRepository(.failure(.serverUnavailable)))
        await #expect(throws: TimelineError.serverUnavailable) { try await sut.execute(in: window) }
    }
}

struct GetCameraPreviewsTests {

    @Test func `given a provider when fetching clips then it forwards them`() async throws {
        let clip = PreviewClip(camera: CameraName("drive"), range: TimeRange(start: at(0), end: at(60)), path: "/p.mp4")
        let sut = GetCameraPreviews(provider: FakePreviewProvider(stubClips: [clip]))
        #expect(try await sut.clips(for: CameraName("drive"), in: window) == [clip])
    }

    @Test func `given a clip when resolving its source then it forwards the provider source`() {
        let clip = PreviewClip(camera: CameraName("drive"), range: TimeRange(start: at(0), end: at(60)), path: "/p.mp4")
        let source = CameraStreamSource(url: URL(string: "http://h/p.mp4")!, headers: ["Authorization": "x"])
        let sut = GetCameraPreviews(provider: FakePreviewProvider(stubSource: source))
        #expect(sut.clipSource(clip) == source)
    }
}

// MARK: - Helpers

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private let window = TimeRange(start: at(0), end: at(100))

private struct FakeTimelineRepository: CameraDayTimelineRepository {
    let result: Result<DayTimeline, TimelineError>
    init(_ result: Result<DayTimeline, TimelineError>) { self.result = result }
    func dayTimeline(in range: TimeRange) async throws(TimelineError) -> DayTimeline { try result.get() }
}

private struct FakePreviewProvider: CameraPreviewProviding {
    var stubClips: [PreviewClip] = []
    var stubFrames: [PreviewFrame] = []
    var stubSource = CameraStreamSource(url: URL(string: "http://h")!, headers: [:])
    func clips(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewClip] { stubClips }
    func frames(for camera: CameraName, in range: TimeRange) async throws(TimelineError) -> [PreviewFrame] { stubFrames }
    func clipSource(_ clip: PreviewClip) -> CameraStreamSource { stubSource }
}
