import Foundation
import Testing

import CamerasEntities
import TestDoubles
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

struct PreviewFrameTests {

    @Test func `given frames when finding the most recent at or before a time then it is returned`() {
        let frames = [frame(10), frame(20), frame(30)]
        #expect(frames.mostRecent(atOrBefore: at(25)) == frame(20))
        #expect(frames.mostRecent(atOrBefore: at(30)) == frame(30))
    }

    @Test func `given a time before every frame then there is none`() {
        #expect([frame(10), frame(20)].mostRecent(atOrBefore: at(5)) == nil)
    }

    @Test func `given no frames then there is none`() {
        #expect([PreviewFrame]().mostRecent(atOrBefore: at(5)) == nil)
    }

    private func frame(_ seconds: TimeInterval) -> PreviewFrame {
        PreviewFrame(camera: CameraName("drive"), time: at(seconds), fileName: "preview_drive-\(Int(seconds)).webp")
    }
}

struct GetDayTimelineTests {

    @Test func `given a repository when executing then it returns the day timeline`() async throws {
        let timeline = DayTimeline(markers: [], motion: [], gaps: [])
        let sut = GetDayTimeline(repository: FakeCameraDayTimelineRepository(.success(timeline)))
        #expect(try await sut.execute(for: .allCameras, in: window) == timeline)
    }

    @Test func `given a failing repository when executing then it propagates the error`() async {
        let sut = GetDayTimeline(repository: FakeCameraDayTimelineRepository(.failure(.serverUnavailable)))
        await #expect(throws: TimelineError.serverUnavailable) {
            try await sut.execute(for: .allCameras, in: window)
        }
    }

    @Test func `given one camera when executing then the repository is asked for that scope`() async throws {
        let repository = FakeCameraDayTimelineRepository(.success(DayTimeline(markers: [], motion: [], gaps: [])))
        let sut = GetDayTimeline(repository: repository)

        _ = try await sut.execute(for: .camera(CameraName("driveway")), in: window)

        #expect(repository.queriedScopes == [.camera(CameraName("driveway"))])
    }
}

struct TimelineScopeTests {

    @Test func `given all cameras then it names none`() {
        #expect(TimelineScope.allCameras.cameraNames.isEmpty)
    }

    @Test func `given one camera then it names that camera`() {
        #expect(TimelineScope.camera(CameraName("driveway")).cameraNames == [CameraName("driveway")])
    }
}

struct GetCameraPreviewsTests {

    @Test func `given a provider when fetching clips then it forwards them`() async throws {
        let clip = PreviewClip(camera: CameraName("drive"), range: TimeRange(start: at(0), end: at(60)), path: "/p.mp4")
        let sut = GetCameraPreviews(provider: FakeCameraPreviewProvider(clips: [clip]))
        #expect(try await sut.clips(for: CameraName("drive"), in: window) == [clip])
    }

    @Test func `given a clip when resolving its source then it forwards the provider source`() {
        let clip = PreviewClip(camera: CameraName("drive"), range: TimeRange(start: at(0), end: at(60)), path: "/p.mp4")
        let source = CameraStreamSource(url: URL(string: "http://h/p.mp4")!, headers: ["Authorization": "x"])
        let sut = GetCameraPreviews(provider: FakeCameraPreviewProvider(source: source))
        #expect(sut.clipSource(clip) == source)
    }
}

// MARK: - Helpers

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private let window = TimeRange(start: at(0), end: at(100))
