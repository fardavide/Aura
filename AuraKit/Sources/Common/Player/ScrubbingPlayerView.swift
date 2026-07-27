import AVKit
import SwiftUI

/// Hosts an externally-owned `AVPlayer` (seeks driven by the caller) with playback controls
/// hidden and Picture-in-Picture off — for scrubbed and custom-transport playback, distinct from
/// the autoplaying `LiveVideoView`.
///
/// `videoGravity` is the caller's: a preview tile fills its 16:9 slot, while a full-screen
/// recording is letterboxed so none of the frame is cropped away.
public struct ScrubbingPlayerView {
    let player: AVPlayer
    let videoGravity: AVLayerVideoGravity

    public init(player: AVPlayer, videoGravity: AVLayerVideoGravity) {
        self.player = player
        self.videoGravity = videoGravity
    }
}

#if os(iOS)
extension ScrubbingPlayerView: UIViewControllerRepresentable {
    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = videoGravity
        controller.player = player
        return controller
    }

    public func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.videoGravity = videoGravity
        controller.player = player
    }
}
#elseif os(macOS)
extension ScrubbingPlayerView: NSViewRepresentable {
    public func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.allowsPictureInPicturePlayback = false
        view.videoGravity = videoGravity
        view.player = player
        return view
    }

    public func updateNSView(_ view: AVPlayerView, context: Context) {
        view.videoGravity = videoGravity
        view.player = player
    }
}
#endif
