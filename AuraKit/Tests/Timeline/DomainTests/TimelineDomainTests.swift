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

struct OverlayWindowTests {

    @Test func `given a span within one day then a single window covers it`() {
        #expect(
            OverlayWindow.windows(covering: TimeRange(start: at(1000), end: at(5000)))
                == [TimeRange(start: at(1000), end: at(5000))]
        )
    }

    @Test func `given a multi-day span then day windows walk back from the live edge`() {
        let windows = OverlayWindow.windows(covering: TimeRange(start: at(0), end: at(200_000)))
        #expect(windows == [
            TimeRange(start: at(113_600), end: at(200_000)),
            TimeRange(start: at(27_200), end: at(113_600)),
            TimeRange(start: at(0), end: at(27_200)),
        ])
    }

    @Test func `given a fractional live edge then the seams land on whole seconds`() {
        let windows = OverlayWindow.windows(covering: TimeRange(start: at(0), end: at(100_000.7)))
        #expect(windows == [
            TimeRange(start: at(13_600), end: at(100_000.7)),
            TimeRange(start: at(0), end: at(13_600)),
        ])
    }

    @Test func `given an empty range then there are no windows`() {
        #expect(OverlayWindow.windows(covering: TimeRange(start: at(50), end: at(50))).isEmpty)
    }

    @Test func `given a short span then buckets floor at one minute`() {
        #expect(OverlayWindow.bucketDuration(for: TimeRange(start: at(0), end: at(3600))) == 60)
    }

    @Test func `given a week-long span then buckets keep the strip near two thousand points`() {
        #expect(OverlayWindow.bucketDuration(for: TimeRange(start: at(0), end: at(604_800))) == 302)
    }

    @Test func `given a refresh then it reaches one bucket and a segment behind the previous edge`() {
        #expect(
            OverlayWindow.refresh(previousEnd: at(10_000), now: at(10_030), bucket: 300)
                == TimeRange(start: at(9640), end: at(10_030))
        )
    }
}

struct DayTimelineReplacingTests {

    @Test func `given cached overlays when a window lands then only its stretch is replaced`() {
        // given — cached content on both sides of the window and inside it
        let cached = DayTimeline(
            markers: [marker(100, 200), marker(1100, 1200), marker(2100, 2200)],
            motion: [bucket(100), bucket(1100), bucket(2100)],
            gaps: [gap(150, 250), gap(1150, 1250)]
        )
        let slice = DayTimelineSlice(
            window: TimeRange(start: at(1000), end: at(2000)),
            overlays: DayTimeline(markers: [marker(1500, 1600)], motion: [bucket(1500)], gaps: [gap(1500, 1600)])
        )

        // when
        let merged = cached.replacing(slice)

        // then — outside kept, inside superseded
        #expect(merged.markers == [marker(100, 200), marker(1500, 1600), marker(2100, 2200)])
        #expect(merged.motion == [bucket(100), bucket(1500), bucket(2100)])
        #expect(merged.gaps == [gap(150, 250), gap(1500, 1600)])
    }

    @Test func `given an in-progress marker when a later window lands then the fresh copy wins`() {
        // given — an in-progress alert cached from the previous read, reaching to the present
        let cached = DayTimeline(
            markers: [ReviewMarker(start: at(500), end: nil, severity: .alert)], motion: [], gaps: []
        )
        // the fresh read shows it finished
        let slice = DayTimelineSlice(
            window: TimeRange(start: at(1000), end: at(2000)),
            overlays: DayTimeline(
                markers: [ReviewMarker(start: at(500), end: at(1200), severity: .alert)], motion: [], gaps: []
            )
        )

        // when
        let merged = cached.replacing(slice)

        // then — one marker, the finished one, kept whole even though it starts before the window
        #expect(merged.markers == [ReviewMarker(start: at(500), end: at(1200), severity: .alert)])
    }

    @Test func `given slice content outside its window then it is ignored`() {
        // given — a response carrying more than its window, as an overlap query does
        let slice = DayTimelineSlice(
            window: TimeRange(start: at(1000), end: at(2000)),
            overlays: DayTimeline(markers: [marker(100, 200)], motion: [bucket(2500)], gaps: [gap(2500, 2600)])
        )

        // when
        let merged = DayTimeline(markers: [], motion: [], gaps: []).replacing(slice)

        // then
        #expect(merged == DayTimeline(markers: [], motion: [], gaps: []))
    }

    @Test func `given a gap crossing the seam then the pieces weld back into one`() {
        // given — the tail of the gap already cached by the newer window's read
        let cached = DayTimeline(markers: [], motion: [], gaps: [gap(1000, 1400)])
        // the older window lands with the head of the same gap, ending exactly on the seam
        let slice = DayTimelineSlice(
            window: TimeRange(start: at(0), end: at(1000)),
            overlays: DayTimeline(markers: [], motion: [], gaps: [gap(600, 1000)])
        )

        // when
        let merged = cached.replacing(slice)

        // then
        #expect(merged.gaps == [gap(600, 1400)])
    }

    @Test func `given a cached gap straddling the window then the covered part is re-judged`() {
        // given — a cached gap reaching into the window; the fresh read shows footage there
        let cached = DayTimeline(markers: [], motion: [], gaps: [gap(500, 1500)])
        let slice = DayTimelineSlice(
            window: TimeRange(start: at(1000), end: at(2000)),
            overlays: DayTimeline(markers: [], motion: [], gaps: [])
        )

        // when
        let merged = cached.replacing(slice)

        // then — only the uncovered head survives
        #expect(merged.gaps == [gap(500, 1000)])
    }

    @Test func `given a bucket on the window's start edge then it belongs to the window`() {
        // given
        let cached = DayTimeline(markers: [], motion: [bucket(1000)], gaps: [])
        let slice = DayTimelineSlice(
            window: TimeRange(start: at(1000), end: at(2000)),
            overlays: DayTimeline(markers: [], motion: [], gaps: [])
        )

        // when - then — the window is half-open, so its start-edge bucket is replaced
        #expect(cached.replacing(slice).motion.isEmpty)
    }
}

struct GetDayTimelineTests {

    @Test func `given a two-day range when executing then one slice per day arrives newest first`() async {
        // given
        let overlays = DayTimeline(markers: [], motion: [bucket(150_000)], gaps: [])
        let repository = FakeCameraDayTimelineRepository(.success(overlays))
        let sut = GetDayTimeline(repository: repository)

        // when
        let slices = await collect(sut.execute(for: .allCameras, in: TimeRange(start: at(0), end: at(172_800)), bucket: 60))

        // then
        let expectedWindows = [
            TimeRange(start: at(86_400), end: at(172_800)),
            TimeRange(start: at(0), end: at(86_400)),
        ]
        #expect(slices.map(\.window) == expectedWindows)
        #expect(repository.queriedRanges == expectedWindows)
        #expect(slices.map(\.overlays) == [overlays, overlays])
    }

    @Test func `given one camera when executing then scope and bucket reach every window's query`() async {
        // given
        let repository = FakeCameraDayTimelineRepository(.success(DayTimeline(markers: [], motion: [], gaps: [])))
        let sut = GetDayTimeline(repository: repository)

        // when
        _ = await collect(
            sut.execute(for: .camera(CameraName("driveway")), in: TimeRange(start: at(0), end: at(172_800)), bucket: 302)
        )

        // then
        #expect(repository.queriedScopes == [.camera(CameraName("driveway")), .camera(CameraName("driveway"))])
        #expect(repository.queriedBuckets == [302, 302])
    }

    @Test func `given an unreachable server when executing then the walk stops at the first window`() async {
        // given
        let repository = FakeCameraDayTimelineRepository(.failure(.unreachable))
        let sut = GetDayTimeline(repository: repository)

        // when
        let slices = await collect(sut.execute(for: .allCameras, in: TimeRange(start: at(0), end: at(259_200)), bucket: 60))

        // then — no slices, and the remaining days were never asked for
        #expect(slices.isEmpty)
        #expect(repository.queriedRanges.count == 1)
    }

    @Test func `given a failure on the second window then the first slice stands and the walk stops`() async {
        // given — the server answers one window, then goes down
        let repository = FakeCameraDayTimelineRepository(.success(DayTimeline(markers: [], motion: [], gaps: [])))
        repository.onQuery = { [weak repository] in
            guard let repository, repository.queriedRanges.count == 2 else { return }
            repository.result = .failure(.unreachable)
        }
        let sut = GetDayTimeline(repository: repository)

        // when
        let slices = await collect(sut.execute(for: .allCameras, in: TimeRange(start: at(0), end: at(259_200)), bucket: 60))

        // then
        #expect(slices.count == 1)
        #expect(repository.queriedRanges.count == 2)
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

private func marker(_ start: TimeInterval, _ end: TimeInterval) -> ReviewMarker {
    ReviewMarker(start: at(start), end: at(end), severity: .alert)
}

private func bucket(_ time: TimeInterval) -> MotionBucket {
    MotionBucket(time: at(time), intensity: 50)
}

private func gap(_ start: TimeInterval, _ end: TimeInterval) -> FootageGap {
    FootageGap(range: TimeRange(start: at(start), end: at(end)))
}

private func collect(_ stream: AsyncStream<DayTimelineSlice>) async -> [DayTimelineSlice] {
    var slices: [DayTimelineSlice] = []
    for await slice in stream {
        slices.append(slice)
    }
    return slices
}
