import AVFoundation
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Renders the live video and nothing else — a bare `AVPlayerLayer`, no transport controls and no
/// built-in gestures. This is the one view placed inside `ZoomableContainer`, so the zoom's
/// `scaleEffect` scales only the video pixels; the overlay controls are siblings that never scale.
/// PiP is wired to the layer via the shared `LivePlayerModel`.
struct LivePlayerView {
    let model: LivePlayerModel
}

#if os(iOS)
extension LivePlayerView: UIViewRepresentable {
    func makeUIView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.playerLayer.player = model.player
        view.playerLayer.videoGravity = .resizeAspect
        model.attach(playerLayer: view.playerLayer)
        return view
    }

    func updateUIView(_ view: PlayerLayerHostView, context: Context) {}
}

/// A `UIView` whose backing layer *is* an `AVPlayerLayer`, so it resizes with the view for free.
final class PlayerLayerHostView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        guard let playerLayer = layer as? AVPlayerLayer else {
            preconditionFailure("layerClass guarantees the backing layer is an AVPlayerLayer")
        }
        return playerLayer
    }
}
#elseif os(macOS)
extension LivePlayerView: NSViewRepresentable {
    func makeNSView(context: Context) -> PlayerLayerHostView {
        let view = PlayerLayerHostView()
        view.playerLayer.player = model.player
        view.playerLayer.videoGravity = .resizeAspect
        model.attach(playerLayer: view.playerLayer)
        return view
    }

    func updateNSView(_ view: PlayerLayerHostView, context: Context) {}
}

/// An `NSView` whose backing layer is an `AVPlayerLayer` (via `makeBackingLayer`), so it resizes
/// with the view for free — the AppKit mirror of iOS's `layerClass` override.
final class PlayerLayerHostView: NSView {
    var playerLayer: AVPlayerLayer {
        guard let playerLayer = layer as? AVPlayerLayer else {
            preconditionFailure("the backing layer is an AVPlayerLayer")
        }
        return playerLayer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        preconditionFailure("PlayerLayerHostView is created in code, never from a coder")
    }

    override func makeBackingLayer() -> CALayer { AVPlayerLayer() }
}
#endif
