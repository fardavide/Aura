import AVFoundation

import CommonPlayer
import TimelineDomain

@MainActor
func makeRecordingPlayer(source: RecordingPlaybackSource) async throws(TimelineError) -> AVPlayer {
    switch source {
    case .stream(let stream):
        return makeAuthedPlayer(url: stream.url, headers: stream.headers)
    case .clips(let clips):
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw .invalidData }
        var cursor = CMTime.zero
        do {
            for clip in clips {
                try Task.checkCancellation()
                let asset = makeAuthedAsset(url: clip.source.url, headers: clip.source.headers)
                guard let video = try await asset.loadTracks(withMediaType: .video).first else { throw TimelineError.invalidData }
                let range = CMTimeRange(
                    start: CMTime(seconds: clip.sourceOffset, preferredTimescale: 1_000_000),
                    duration: CMTime(seconds: clip.duration, preferredTimescale: 1_000_000)
                )
                // Container duration can include audio whose timestamps are far beyond video.
                // Only the mapped video interval belongs in this silent fast-forward source.
                try track.insertTimeRange(range, of: video, at: cursor)
                cursor = CMTimeAdd(cursor, range.duration)
            }
        } catch {
            throw .invalidData
        }
        return AVPlayer(playerItem: AVPlayerItem(asset: composition))
    }
}
