import SwiftUI

/// The recordings player's on-screen composition: the video filling the screen, with the transport
/// overlaid along the bottom **inside** the safe area so it never slides under the home indicator.
/// Split out from `RecordingPlayerView` so this layout can be snapshot-tested over a placeholder,
/// with a fixed control state and no real player.
///
/// `controls` is absent while the first load is in flight or the server is unreachable — there is
/// nothing to transport in either case.
public struct RecordingPlayerLayout<Video: View>: View {
    private let controls: RecordingControlBar?
    private let video: Video

    public init(controls: RecordingControlBar?, @ViewBuilder video: () -> Video) {
        self.controls = controls
        self.video = video()
    }

    public var body: some View {
        video
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { controls }
    }
}
