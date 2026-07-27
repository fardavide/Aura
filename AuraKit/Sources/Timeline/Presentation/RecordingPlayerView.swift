import AVFoundation
import SwiftUI

import CommonPlayer

/// Full-resolution playback of one camera's recordings, with the transport floated over the video.
public struct RecordingPlayerView: View {
    // @State-pinned like the sibling screens: the composition root builds a fresh view model on
    // every re-evaluation, and the `.task` below binds only on appearance — a plain `let` would
    // leave the displayed model waiting on a load that ran against a discarded one.
    @State private var viewModel: RecordingPlayerViewModel

    public init(viewModel: RecordingPlayerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        RecordingPlayerLayout(controls: controls) {
            content
        }
        .navigationTitle(viewModel.camera.friendlyName ?? viewModel.camera.name.value)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        #endif
        .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.display {
        case .loading:
            ProgressView()
        case .ready(let player):
            // Letterboxed, not filled: the point of this screen is the whole recorded frame.
            ScrubbingPlayerView(player: player, videoGravity: .resizeAspect)
                .background(.black)
        case .noFootage:
            ContentUnavailableView(
                "No recording",
                systemImage: "clock.badge.questionmark",
                description: Text("Nothing was recorded in this hour.")
            )
        case .failed:
            ContentUnavailableView(
                "Can't reach the server",
                systemImage: "wifi.slash",
                description: Text("Check your connection settings.")
            )
        }
    }

    /// Present over playable states only — there is nothing to transport while the first load is in
    /// flight or the server is unreachable, but an empty hour still needs the skip out of it.
    private var controls: RecordingControlBar? {
        let isPlayable: Bool
        switch viewModel.display {
        case .loading, .failed: return nil
        case .ready: isPlayable = true
        case .noFootage: isPlayable = false
        }
        return RecordingControlBar(
            state: RecordingControlState(
                instant: viewModel.instant,
                isPlaying: viewModel.isPlaying,
                speed: viewModel.speed,
                hasFootage: viewModel.hasFootage,
                isPlayable: isPlayable
            ),
            onPlayPause: { viewModel.togglePlayPause() },
            onSkip: { seconds in Task { await viewModel.skip(by: seconds) } },
            onSelectSpeed: { viewModel.select($0) }
        )
    }
}
