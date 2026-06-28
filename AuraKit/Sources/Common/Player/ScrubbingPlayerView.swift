import AVKit
import SwiftUI

/// Hosts an externally-owned `AVPlayer` (seeks driven by the caller) with playback controls
/// hidden and Picture-in-Picture off — for scrub-only preview tiles, distinct from the
/// autoplaying `VideoPlayerView`.
public struct ScrubbingPlayerView {
    let player: AVPlayer

    public init(player: AVPlayer) {
        self.player = player
    }
}

#if os(iOS)
extension ScrubbingPlayerView: UIViewControllerRepresentable {
    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.allowsPictureInPicturePlayback = false
        controller.videoGravity = .resizeAspectFill
        controller.player = player
        return controller
    }

    public func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.player = player
    }
}
#elseif os(macOS)
extension ScrubbingPlayerView: NSViewRepresentable {
    public func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.allowsPictureInPicturePlayback = false
        view.videoGravity = .resizeAspectFill
        view.player = player
        return view
    }

    public func updateNSView(_ view: AVPlayerView, context: Context) {
        view.player = player
    }
}
#endif
