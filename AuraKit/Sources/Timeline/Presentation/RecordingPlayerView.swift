import AVFoundation
import SwiftUI

import CamerasDomain
import CommonDesign
import CommonPlayer

/// Full-resolution playback of one camera's recordings against its own time axis — the screen a
/// tile in the Timeline grid opens.
public struct RecordingPlayerView: View {
    public typealias ModelFactory = (Camera, Date, RecordingPlayerViewModel.StartMode) -> RecordingPlayerViewModel
    public typealias PreviewLoader = @MainActor (Camera, Date) async -> Image?

    // @State-pinned like the sibling screens: the composition root builds a fresh view model on
    // every re-evaluation, and the `.task`s below bind only on appearance — a plain `let` would
    // leave the displayed model waiting on a load that ran against a discarded one.
    @State private var viewModel: RecordingPlayerViewModel
    @Environment(\.scenePhase) private var scenePhase
    private let cameras: [Camera]
    private let makeViewModel: ModelFactory
    private let loadPreview: PreviewLoader
    /// How a finished clip is reached from here. The tab bar is hidden on this screen, so there is
    /// no badge to light up — the way across has to be a control the panel owns.
    private let onOpenExports: () -> Void

    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    public init(
        viewModel: RecordingPlayerViewModel,
        cameras: [Camera],
        makeViewModel: @escaping ModelFactory,
        loadPreview: @escaping PreviewLoader,
        onOpenExports: @escaping () -> Void
    ) {
        _viewModel = State(initialValue: viewModel)
        self.cameras = cameras
        self.makeViewModel = makeViewModel
        self.loadPreview = loadPreview
        self.onOpenExports = onOpenExports
    }

    public var body: some View {
        RecordingDetailLayout(
            state: viewModel.state,
            actions: actions,
            filmstrip: viewModel.filmstrip,
            retryLive: retryLive,
            railHeader: cameraMenu
        ) {
            content
        }
        .id(viewModel.camera.id)
        .navigationTitle(viewModel.camera.friendlyName ?? viewModel.camera.name.value)
        .toolbar {
            if !usesCompactRail {
                ToolbarItem(placement: .principal) { cameraMenu }
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar(usesCompactRail ? .hidden : .visible, for: .navigationBar)
        #endif
        .task(id: viewModel.camera.id) { [viewModel] in await viewModel.loadIfNeeded() }
        .task(id: viewModel.camera.id) { [viewModel] in await viewModel.autoRefresh() }
        .onDisappear { viewModel.stopLivePlayback() }
        .onChange(of: scenePhase) { _, phase in viewModel.handleScenePhase(phase) }
    }

    private var usesCompactRail: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }

    @ViewBuilder private var cameraMenu: some View {
        if cameras.count > 1 && !viewModel.state.isExporting {
            AuroraPreviewMenu(
                selected: viewModel.camera,
                options: cameras,
                name: { $0.friendlyName ?? $0.name.value },
                captureContext: { (instant: viewModel.instant, isPlaying: viewModel.isPlaying) },
                caption: { context in
                    Text(context.instant, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                },
                loadPreview: { camera, context in await loadPreview(camera, context.instant) },
                onSelect: { camera, context in
                    viewModel.stopPlaybackForCameraSwitch()
                    viewModel = makeViewModel(camera, context.instant, .cameraSwitch(isPlaying: context.isPlaying))
                }
            )
        }
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

    private var retryLive: (() -> Void)? {
        guard case .live = viewModel.display, viewModel.state.slot == .failed else { return nil }
        return { Task { await viewModel.goLive() } }
    }

    private var actions: RecordingDetailActions {
        // A disappearing panel may still settle its scrub. It belongs to the player that
        // owned it, even if a camera selection has already installed a new player.
        let viewModel = self.viewModel
        return RecordingDetailActions(
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
