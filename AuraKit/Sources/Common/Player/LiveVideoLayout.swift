import SwiftUI

/// The live view's on-screen composition: video filling the screen **behind** the safe area, with
/// the transport controls overlaid **inside** it. Only the video takes `ignoresSafeArea`, so the
/// controls (and the LIVE badge) never slide under the status bar / notch. Split out from
/// `LiveVideoView` so this layout — the safe-area behavior included — can be snapshot-tested with a
/// placeholder video and a fixed control state, without constructing a real player.
public struct LiveVideoLayout<Video: View>: View {
    private let controls: LiveControlBar
    private let areControlsVisible: Bool
    private let onSingleTap: () -> Void
    private let video: Video

    public init(
        controls: LiveControlBar,
        areControlsVisible: Bool,
        onSingleTap: @escaping () -> Void,
        @ViewBuilder video: () -> Video
    ) {
        self.controls = controls
        self.areControlsVisible = areControlsVisible
        self.onSingleTap = onSingleTap
        self.video = video()
    }

    public var body: some View {
        ZStack {
            ZoomableContainer(onSingleTap: onSingleTap, clipsContent: true) {
                video
            }
            .background(.black)
            .ignoresSafeArea()

            controls
                .opacity(areControlsVisible ? 1 : 0)
                .allowsHitTesting(areControlsVisible)
                .animation(.easeInOut(duration: 0.2), value: areControlsVisible)
        }
    }
}
