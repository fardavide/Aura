#if os(iOS)
import AVFoundation
import UIKit
#endif
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
    public func makeCoordinator() -> Coordinator { Coordinator(url: url, headers: headers) }

    public func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        let player = makeAuthedPlayer(url: url, headers: headers)
        controller.player = player
        player.play()
        context.coordinator.observeInterruptions(of: player)
        disableBuiltInZoomGestures(in: controller.view)
        return controller
    }

    public func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        // AVKit installs its zoom recognizers lazily, so re-assert on every update to keep them off.
        disableBuiltInZoomGestures(in: controller.view)
    }

    /// `AVPlayerViewController` ships its own pinch-to-zoom (video aspect fit↔fill) and a double-tap
    /// zoom, installed on private descendant views. They race `ZoomableContainer`'s gestures — the
    /// built-in pinch snaps the video to center and desyncs our clamped pan, and its two-tap
    /// recognizer collides with our double-tap toggle. There's no public switch, so walk the view
    /// tree and disable those recognizers by kind; single-tap controls and the PiP button (which we
    /// keep for free PiP) stay untouched. macOS's `AVPlayerView` has no such on-glass gesture, so
    /// only iOS needs this.
    private func disableBuiltInZoomGestures(in view: UIView) {
        for recognizer in view.gestureRecognizers ?? [] {
            if recognizer is UIPinchGestureRecognizer
                || (recognizer as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 {
                recognizer.isEnabled = false
            }
        }
        for subview in view.subviews {
            disableBuiltInZoomGestures(in: subview)
        }
    }

    @MainActor
    public final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        private let url: URL
        private let headers: [String: String]
        private weak var player: AVPlayer?
        // Written once during setup, read once in the nonisolated `deinit`; the escape hatch lets
        // deinit unregister the non-Sendable observer token.
        private nonisolated(unsafe) var interruptionObserver: (any NSObjectProtocol)?

        init(url: URL, headers: [String: String]) {
            self.url = url
            self.headers = headers
            super.init()
        }

        deinit {
            if let interruptionObserver {
                NotificationCenter.default.removeObserver(interruptionObserver)
            }
        }

        /// An audio-session interruption (a call, Siri, another app playing audio) pauses the
        /// player and deactivates our session. A *live* HLS item can't be un-paused: while it sat
        /// idle, its segments rolled off the live window, so `play()` has nothing left to show.
        /// Recover when the interruption ends by reactivating the session and swapping in a fresh
        /// live item, which snaps playback back to the live edge. Delivered on the main queue so the
        /// player is touched on its actor.
        func observeInterruptions(of player: AVPlayer) {
            self.player = player
            interruptionObserver = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: AVAudioSession.sharedInstance(),
                queue: .main
            ) { [weak self] notification in
                let ended = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended
                guard ended else { return }
                MainActor.assumeIsolated { self?.resumeAtLiveEdge() }
            }
        }

        /// "Return to app" from the PiP window: the detail view is still in the navigation
        /// stack, so report the UI as already restored for a seamless hand-back. `nonisolated` to
        /// match the delegate requirement — it only forwards the completion handler.
        nonisolated public func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }

        private func resumeAtLiveEdge() {
            try? AVAudioSession.sharedInstance().setActive(true)
            guard let player else { return }
            player.replaceCurrentItem(with: makeAuthedPlayerItem(url: url, headers: headers))
            player.play()
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
