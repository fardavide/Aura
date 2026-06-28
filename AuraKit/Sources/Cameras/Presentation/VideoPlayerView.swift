import AVKit
import SwiftUI

import CamerasDomain

/// The cross-platform live-video host — the one place the player APIs differ by platform:
/// `AVPlayerViewController` on iOS (free PiP), `AVPlayerView` on macOS.
struct VideoPlayerView {
    let source: CameraStreamSource
}

#if os(iOS)
extension VideoPlayerView: UIViewControllerRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.delegate = context.coordinator
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.player = makePlayer(source)
        controller.player?.play()
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}

    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
        /// "Return to app" from the PiP window: the detail view is still in the navigation
        /// stack, so report the UI as already restored for a seamless hand-back.
        func playerViewController(
            _ playerViewController: AVPlayerViewController,
            restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(true)
        }
    }
}
#elseif os(macOS)
extension VideoPlayerView: NSViewRepresentable {
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.allowsPictureInPicturePlayback = true
        view.player = makePlayer(source)
        view.player?.play()
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {}
}
#endif

private func makePlayer(_ source: CameraStreamSource) -> AVPlayer {
    // AVURLAssetHTTPHeaderFieldsKey carries the auth header onto the media request.
    let options = source.headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": source.headers]
    let asset = AVURLAsset(url: source.url, options: options)
    return AVPlayer(playerItem: AVPlayerItem(asset: asset))
}
