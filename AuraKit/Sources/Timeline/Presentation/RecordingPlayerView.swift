import AVFoundation
import SwiftUI

import CommonPlayer

/// Full-resolution playback of one camera's recordings against its own time axis — the screen a
/// tile in the Timeline grid opens.
public struct RecordingPlayerView: View {
    // @State-pinned like the sibling screens: the composition root builds a fresh view model on
    // every re-evaluation, and the `.task`s below bind only on appearance — a plain `let` would
    // leave the displayed model waiting on a load that ran against a discarded one.
    @State private var viewModel: RecordingPlayerViewModel

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    public init(viewModel: RecordingPlayerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        RecordingDetailLayout(state: viewModel.state, actions: actions) {
            content
        }
        .navigationTitle(viewModel.camera.friendlyName ?? viewModel.camera.name.value)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        // A phone on its side is wide but short, and the footage goes full-bleed there — the
        // camera's name is already on the hero, so the title bar is only height taken from it.
        .toolbar(verticalSizeClass == .compact ? .hidden : .visible, for: .navigationBar)
        #endif
        .task { await viewModel.loadIfNeeded() }
        .task { await viewModel.autoRefresh() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.display {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .ready(let player):
            // Letterboxed, not filled: the point of this screen is the whole recorded frame.
            ScrubbingPlayerView(player: player, videoGravity: .resizeAspect)
        case .noFootage:
            // The hero overlay says what's missing and when — nothing to add behind it.
            Color.clear
        case .failed:
            ContentUnavailableView(
                "Can't reach the server",
                systemImage: "wifi.slash",
                description: Text("Check your connection settings.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var actions: RecordingDetailActions {
        RecordingDetailActions(
            playPause: { viewModel.togglePlayPause() },
            skip: { seconds in Task { await viewModel.skip(by: seconds) } },
            selectSpeed: { viewModel.select($0) },
            selectZoom: { viewModel.select($0) },
            beginScrub: { viewModel.beginScrub() },
            scrub: { viewModel.scrub(to: $0) },
            endScrub: { Task { await viewModel.endScrub() } },
            seek: { instant in Task { await viewModel.seek(to: instant) } },
            stepDay: { days in Task { await viewModel.stepDay(by: days) } },
            previousMarker: { Task { await viewModel.jumpToPreviousMarker() } },
            nextMarker: { Task { await viewModel.jumpToNextMarker() } },
            goLive: { Task { await viewModel.goLive() } }
        )
    }
}
