import AVKit
import Foundation
import Observation

import CommonPlayer
import ExportsDomain

/// Plays one finished export. The clip streams from the server with the connection's auth headers
/// — playing never downloads, which is why a copy running beside it changes nothing here.
@Observable
@MainActor
public final class ExportPlayerViewModel {
    public let export: Export
    public private(set) var isPlaying = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0

    @ObservationIgnored public let player: AVPlayer
    @ObservationIgnored private var timeObserver: Any?

    public init(export: Export, playback: any ExportPlaybackProviding) {
        self.export = export
        let source = playback.playbackSource(for: export)
        player = makeAuthedPlayer(url: source.url, headers: source.headers)
    }

    /// The length the server never reports in its export record — the file itself knows it, so the
    /// player is the one place a duration can honestly be shown.
    public func start() async {
        observeTime()
        duration = (try? await player.currentItem?.asset.load(.duration).seconds) ?? 0
        if duration.isNaN || duration.isInfinite { duration = 0 }
        play()
    }

    public func stop() {
        player.pause()
        isPlaying = false
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
    }

    public func togglePlayback() {
        isPlaying ? pause() : play()
    }

    public func skip(_ seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    public func seek(to time: TimeInterval) {
        let clamped = min(max(0, time), duration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func play() {
        player.play()
        isPlaying = true
    }

    private func pause() {
        player.pause()
        isPlaying = false
    }

    private func observeTime() {
        guard timeObserver == nil else { return }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.currentTime = time.seconds.isFinite ? time.seconds : 0
            }
        }
    }
}
