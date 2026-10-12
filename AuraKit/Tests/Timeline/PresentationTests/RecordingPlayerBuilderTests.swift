import AVFoundation
import Foundation
import Testing

import CamerasEntities
import TimelineDomain
@testable import TimelinePresentation

@MainActor
struct RecordingPlayerBuilderTests {
    @Test func `given recording files with offset audio when building fast forward then only bounded video is composed`() async throws {
        // given
        let scenario = try Scenario()

        // when
        let player = try await makeRecordingPlayer(source: .clips(scenario.clips))
        let item = try #require(player.currentItem)
        let duration = try await item.asset.load(.duration)
        let audioTracks = try await item.asset.loadTracks(withMediaType: .audio)

        // then
        #expect(abs(duration.seconds - 1.75) < 0.001)
        #expect(audioTracks.isEmpty)
        #expect(item.asset is AVComposition)
    }

    private struct Scenario {
        let clips: [RecordingClip]

        init() throws {
            let url = try #require(Bundle.module.url(forResource: "recording", withExtension: "mp4", subdirectory: "Fixtures"))
            let source = CameraStreamSource(url: url, headers: [:])
            clips = [
                RecordingClip(source: source, range: TimeRange(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 101)), sourceOffset: 0.5, duration: 1),
                RecordingClip(source: source, range: TimeRange(start: Date(timeIntervalSince1970: 110), end: Date(timeIntervalSince1970: 110.75)), sourceOffset: 0, duration: 0.75),
            ]
        }
    }
}
