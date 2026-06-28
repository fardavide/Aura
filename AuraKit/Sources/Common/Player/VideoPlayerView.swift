import AVKit
import SwiftUI

/// The cross-platform live-video host — the one place the player APIs differ by platform:
/// `AVPlayerViewController` on iOS (free PiP), `AVPlayerView` on macOS. Builds and autoplays
/// its own player from the stream URL + auth headers.
public struct VideoPlayerView {
    let url: URL
    let headers: [String: String]

    public init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
    }
}

#if os(iOS)
extension VideoPlayerView: UIViewControllerRepresentable {
    public func makeCoordinator() -> Coordinator { Coordinator() }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.player = makeAuthedPlayer(url: url, headers: headers)
        controller.player?.play()
        return controller
    }

    public func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    public final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        /// "Return to app" from the PiP window: the detail view is still in the navigation
        /// stack, so report the UI as already restored for a seamless hand-back.
        public func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }
    }
}
#elseif os(macOS)
extension VideoPlayerView: NSViewRepresentable {
    public func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.allowsPictureInPicturePlayback = true
        view.player = makeAuthedPlayer(url: url, headers: headers)
        view.player?.play()
        return view
    }

    public func updateNSView(_ view: AVPlayerView, context: Context) {}
}
#endif
