import Foundation
import Testing

import CamerasEntities
import TestDoubles
@testable import TimelineDomain

struct RecordingWindowTests {

    @Test func `given an instant mid-hour when choosing its window then it spans that whole hour`() {
        // given - when
        let window = RecordingWindow.containing(at(3661))

        // then
        #expect(window == TimeRange(start: at(3600), end: at(7200)))
    }

    @Test func `given an instant on the hour then the window starts there`() {
        #expect(RecordingWindow.containing(at(3600)) == TimeRange(start: at(3600), end: at(7200)))
    }

    @Test func `given a fractional instant when choosing a window then both bounds are whole seconds`() {
        #expect(RecordingWindow.containing(at(3661.7)) == TimeRange(start: at(3600), end: at(7200)))
    }

    // Window identity is what "am I still in the loaded window?" is asked against, so it must not
    // drift as the hour fills up — two instants in the same hour always name the same window.
    @Test func `given two instants in the same hour then they choose the same window`() {
        #expect(RecordingWindow.containing(at(3601)) == RecordingWindow.containing(at(7199)))
    }
}

struct RecordingTimelineTests {

    // MARK: - Playable duration

    @Test func `given no segments then there is nothing playable`() {
        #expect(RecordingTimeline(window: TimeRange(start: at(0), end: at(1000)), segments: []).playableDuration == 0)
    }

    @Test func `given gapped segments when measuring the playable duration then the gaps count for nothing`() {
        #expect(gapped.playableDuration == 90)
    }

    @Test func `given a segment starting before the window then its head is trimmed off`() {
        // given
        let timeline = RecordingTimeline(
            window: TimeRange(start: at(100), end: at(200)),
            segments: [segment(from: 50, to: 150)]
        )

        // then
        #expect(timeline.playableDuration == 50)
        #expect(timeline.playerTime(at: at(100)) == 0)
    }

    @Test func `given a segment ending after the window then its tail is trimmed off`() {
        // given
        let timeline = RecordingTimeline(
            window: TimeRange(start: at(100), end: at(200)),
            segments: [segment(from: 150, to: 250)]
        )

        // then
        #expect(timeline.playableDuration == 50)
    }

    @Test func `given a segment outside the window then it contributes nothing`() {
        // given
        let timeline = RecordingTimeline(
            window: TimeRange(start: at(100), end: at(200)),
            segments: [segment(from: 0, to: 100), segment(from: 200, to: 300)]
        )

        // then
        #expect(timeline.playableDuration == 0)
    }

    // The server drops a clip whose trimmed duration falls under 100ms — mirror it, or every
    // later instant in the window maps a sliver too far into the stream.
    @Test func `given a segment trimmed shorter than the server minimum then it is dropped`() {
        // given
        let timeline = RecordingTimeline(
            window: TimeRange(start: at(100), end: at(200)),
            segments: [segment(from: 99.95, to: 100.02)]
        )

        // then
        #expect(timeline.playableDuration == 0)
    }

    @Test func `given a segment longer than the server maximum then it is dropped`() {
        // given
        let timeline = RecordingTimeline(
            window: TimeRange(start: at(0), end: at(4000)),
            segments: [segment(from: 0, to: 700)]
        )

        // then
        #expect(timeline.playableDuration == 0)
    }

    @Test func `given a reported duration that disagrees with the span then the duration drives the mapping`() {
        // given — the first segment spans 60s but only 50s of footage was encoded
        let timeline = RecordingTimeline(
            window: TimeRange(start: at(0), end: at(1000)),
            segments: [segment(from: 0, to: 60, duration: 50), segment(from: 100, to: 160)]
        )

        // then
        #expect(timeline.playableDuration == 110)
        #expect(timeline.instant(atPlayerTime: 50) == at(100))
    }

    @Test func `given unordered segments when building then they are read in start order`() {
        // given
        let timeline = RecordingTimeline(
            window: TimeRange(start: at(0), end: at(1000)),
            segments: [segment(from: 500, to: 530), segment(from: 0, to: 60)]
        )

        // then
        #expect(timeline.instant(atPlayerTime: 70) == at(510))
    }

    // MARK: - Wall clock to player time

    @Test func `given an instant inside a segment when mapping to player time then earlier segments are counted`() {
        // then — 60s of footage precedes the second segment, and the instant is 10s into it
        #expect(gapped.playerTime(at: at(510)) == 70)
    }

    @Test func `given an instant inside a gap when mapping to player time then it lands on the next segment`() {
        // then — the stream holds nothing between 60 and 500, so playback resumes at the next segment
        #expect(gapped.playerTime(at: at(300)) == 60)
    }

    @Test func `given an instant before the first segment when mapping to player time then it is the stream start`() {
        // given
        let timeline = RecordingTimeline(
            window: TimeRange(start: at(0), end: at(1000)),
            segments: [segment(from: 400, to: 460)]
        )

        // then
        #expect(timeline.playerTime(at: at(100)) == 0)
    }

    @Test func `given an instant after the last segment when mapping to player time then it is the stream end`() {
        #expect(gapped.playerTime(at: at(900)) == gapped.playableDuration)
    }

    @Test func `given no segments when mapping an instant then the player time is the stream start`() {
        let timeline = RecordingTimeline(window: TimeRange(start: at(0), end: at(1000)), segments: [])
        #expect(timeline.playerTime(at: at(500)) == 0)
    }

    // MARK: - Player time to wall clock

    @Test func `given a player time inside the first segment when mapping to wall clock then it is that instant`() {
        #expect(gapped.instant(atPlayerTime: 30) == at(30))
    }

    @Test func `given a player time past a gap when mapping to wall clock then the gap is skipped`() {
        // then — 70 is 10s into the second segment, which starts at 500
        #expect(gapped.instant(atPlayerTime: 70) == at(510))
    }

    @Test func `given a player time past the end when mapping to wall clock then it is the last footage instant`() {
        #expect(gapped.instant(atPlayerTime: 5000) == at(530))
    }

    @Test func `given a negative player time when mapping to wall clock then it is the first footage instant`() {
        #expect(gapped.instant(atPlayerTime: -10) == at(0))
    }

    @Test func `given no segments when mapping a player time then it is the window start`() {
        let timeline = RecordingTimeline(window: TimeRange(start: at(100), end: at(1000)), segments: [])
        #expect(timeline.instant(atPlayerTime: 40) == at(100))
    }

    @Test func `given an instant with footage when mapping to player time and back then it is unchanged`() {
        #expect(gapped.instant(atPlayerTime: gapped.playerTime(at: at(520))) == at(520))
    }

    // MARK: - Footage presence

    @Test func `given an instant inside a segment then there is footage there`() {
        #expect(gapped.hasFootage(at: at(10)))
    }

    @Test func `given an instant inside a gap then there is no footage there`() {
        #expect(!gapped.hasFootage(at: at(300)))
    }

    @Test func `given the end instant of a segment then there is no footage there`() {
        #expect(!gapped.hasFootage(at: at(60)))
    }
}

struct GetCameraRecordingsTests {

    @Test func `given segments when getting recordings then they become the window's timeline`() async throws {
        // given
        let repository = FakeCameraRecordingsRepository(.success([segment(from: 0, to: 60)]))
        let sut = GetCameraRecordings(repository: repository)

        // when
        let playback = try await sut.execute(for: CameraName("drive"), in: TimeRange(start: at(0), end: at(1000)))

        // then
        #expect(playback.timeline.playableDuration == 60)
    }

    @Test func `when getting recordings then the source is resolved for the same window`() async throws {
        // given
        let window = TimeRange(start: at(3600), end: at(7200))
        let source = CameraStreamSource(url: URL(string: "http://h/vod/drive/start/3600/end/7200/master.m3u8")!, headers: [:])
        let repository = FakeCameraRecordingsRepository(.success([]), source: source)
        let sut = GetCameraRecordings(repository: repository)

        // when
        let playback = try await sut.execute(for: CameraName("drive"), in: window)

        // then
        #expect(playback.source == source)
        #expect(repository.lastWindow == window)
    }

    @Test func `given a failing repository when getting recordings then it propagates the error`() async {
        // given
        let sut = GetCameraRecordings(repository: FakeCameraRecordingsRepository(.failure(.serverUnavailable)))

        // then
        await #expect(throws: TimelineError.serverUnavailable) {
            try await sut.execute(for: CameraName("drive"), in: TimeRange(start: at(0), end: at(1000)))
        }
    }
}

// MARK: - Helpers

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

/// A segment whose encoded duration matches its span — the ordinary case. Pass `duration`
/// explicitly to model a recording whose file is shorter or longer than the span it covers.
private func segment(from start: TimeInterval, to end: TimeInterval, duration: TimeInterval? = nil) -> RecordingSegment {
    RecordingSegment(range: TimeRange(start: at(start), end: at(end)), duration: duration ?? end - start)
}

/// 60s of footage, a long gap, then 30s more — the shape every mapping case is measured against.
private let gapped = RecordingTimeline(
    window: TimeRange(start: at(0), end: at(1000)),
    segments: [segment(from: 0, to: 60), segment(from: 500, to: 530)]
)
