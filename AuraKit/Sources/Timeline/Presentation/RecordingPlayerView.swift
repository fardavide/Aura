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
    /// How a finished clip is reached from here. The tab bar is hidden on this screen, so there is
    /// no badge to light up — the way across has to be a control the panel owns.
    private let onOpenExports: () -> Void

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    public init(viewModel: RecordingPlayerViewModel, onOpenExports: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onOpenExports = onOpenExports
    }

    public var body: some View {
        RecordingDetailLayout(state: viewModel.state, actions: actions, filmstrip: viewModel.filmstrip) {
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
        if viewModel.isScrubbing {
            scrubContent
        } else {
            recordingContent
        }
    }

    @ViewBuilder private var scrubContent: some View {
        switch viewModel.scrubPreview.display {
        case .clip(let player), .recording(let player):
            ScrubbingPlayerView(player: player, videoGravity: .resizeAspect)
        case .frame(let image):
            image
                .resizable()
                .scaledToFit()
        case .loading, .unavailable, .failed:
            recordingContent
        }
    }

    @ViewBuilder private var recordingContent: some View {
        switch viewModel.display {
        case .ready(let player), .live(let player):
            // Letterboxed, not filled: the point of this screen is the whole recorded frame.
            ScrubbingPlayerView(player: player, videoGravity: .resizeAspect)
        case .loading, .noFootage, .failed:
            // Nothing to draw here: the layout hides the card and says what is missing in the
            // slot's place (`RecordingHeroOverlay`), outside the zoom so the message never scales.
            Color.clear
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
            goLive: { Task { await viewModel.goLive() } },
            beginExport: { viewModel.beginExport() },
            cancelExport: { viewModel.cancelExport() },
            changeSelection: { viewModel.change(selection: $0) },
            resetSelectionToPlayhead: { viewModel.resetSelectionToPlayhead() },
            playSelection: { Task { await viewModel.playSelection() } },
            createExport: { Task { await viewModel.createExport() } },
            viewInExports: onOpenExports,
            playExport: onOpenExports,
            finishExport: { viewModel.finishExport() }
        )
    }
}
