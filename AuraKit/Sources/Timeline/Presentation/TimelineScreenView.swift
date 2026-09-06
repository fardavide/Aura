import SwiftUI

import CamerasDomain
import CamerasEntities
import CommonDesign
import TimelineDomain

public struct TimelineScreenView: View {
    // @State-pinned, like the sibling tabs (CameraGridView, EventsListView): RootView builds a
    // fresh view model on every body re-evaluation (tab switches alone produce two), while the
    // `.task` closures below only rebind on an appearance. A plain `let` let a re-evaluation swap
    // the *displayed* model for a never-loaded one whose only exit from `.loading` — the
    // appearance-driven `loadIfNeeded` — stayed bound to the discarded instance: a permanent
    // full-screen spinner (`shouldRefreshNow` gates every refresh path off while `.loading`).
    // Pinning keeps the first instance for the view's identity lifetime, so the displayed and
    // task-driven model are always the same object; a connection change still rebuilds it via
    // RootView's `.id`.
    @State private var viewModel: TimelineScreenViewModel
    private let makeTileViewModel: (Camera) -> PreviewTileViewModel
    private let makeRecordingPlayerViewModel: (Camera, Date) -> RecordingPlayerViewModel

    @State private var tiles = TileStore()
    @State private var cardHeight: CGFloat = 180
    @State private var openedRecording: RecordingRoute?
    @Environment(\.scenePhase) private var scenePhase
    // Pinned outside the grid's ScrollView (regular height only — compact height hides the header
    // entirely, see `isCompactHeight`'s doc comment), so it needs its own measured height to
    // reserve as top spacing and its own scroll-offset tracking for its glass backing — see
    // `AuroraScrollHeader`'s doc comment for why this is hand-rolled rather than a system toolbar.
    @State private var headerHeight: CGFloat = 0
    @State private var isHeaderGlass = false

    // Read the real size class so the layout re-evaluates on rotation. iOS-only: macOS has no
    // size class, so the side-by-side branch never applies there.
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// True when the vertical size class is compact — in practice iPhone landscape. iPad reports a
    /// regular height in every orientation and multitasking mode (Split View / Stage Manager make
    /// only the *width* compact), and macOS has no size class, so neither takes the side-by-side layout.
    private var isCompactHeight: Bool {
        #if os(iOS)
        verticalSizeClass == .compact
        #else
        false
        #endif
    }

    /// True when the horizontal size class is compact — iPhone portrait and narrow iPad splits.
    /// macOS has no size class, so it always lays out as regular width.
    private var isCompactWidth: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    /// True on iOS regular width (iPad) — the fixed 3-column grid and the large toolbar title.
    /// **macOS keeps `TimelineGridLayout.bestFit`** (0.3.4) and the compact title: it reports
    /// regular width too, but a ~28–38pt Mac title bar would clip a 28pt ExtraBold title or force
    /// the bar to grow, and no snapshot baseline covers macOS. A *platform* discriminator as much
    /// as a size-class one, so it is named for the decision it drives rather than the class it reads.
    private var usesFixedColumnGrid: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        false
        #endif
    }

    public init(
        viewModel: TimelineScreenViewModel,
        makeTileViewModel: @escaping (Camera) -> PreviewTileViewModel,
        makeRecordingPlayerViewModel: @escaping (Camera, Date) -> RecordingPlayerViewModel
    ) {
        _viewModel = State(initialValue: viewModel)
        self.makeTileViewModel = makeTileViewModel
        self.makeRecordingPlayerViewModel = makeRecordingPlayerViewModel
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                content
                    // `.background` (inside `.auroraBackground()`) sizes itself to its content, and
                    // the `.loading` branch is a bare `ProgressView()` — without this the aurora
                    // background would only paint a postage-stamp patch behind it.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .auroraBackground()
                if !isCompactHeight {
                    header
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                }
            }
            .auroraHiddenNavigationBar()
            .navigationDestination(item: $openedRecording) { recording in
                RecordingPlayerView(
                    viewModel: makeRecordingPlayerViewModel(recording.camera, recording.instant)
                )
            }
        }
        .task { await viewModel.loadIfNeeded() }
        .task { await viewModel.autoRefresh() }
        // The playhead's own tick. It runs for the screen's life and does nothing while paused, so
        // play/pause never has to start or stop a task.
        .task { await viewModel.transport.run() }
        // Keeps the hero tile and the tile badges current while the screen is visible — without it
        // they would only update on `load()`/`performRefresh()` and freeze for the whole of playback.
        .task { await viewModel.followHero() }
        // Returning from the background catches up right away instead of waiting for the next
        // tick — the app may have been suspended for hours, leaving the whole screen at the old
        // live edge. Same gate as the periodic tick: never disturbs a scrub or history browsing.
        .task(id: scenePhase) {
            guard scenePhase == .active, viewModel.shouldRefreshNow else { return }
            await viewModel.refresh()
        }
    }

    private var header: some View {
        AuroraScrollHeader(isGlass: isHeaderGlass) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Timeline").auroraText(.screenTitle).foregroundStyle(.auroraTextPrimary)
                TimelineDayLabel(clock: viewModel.clock)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .empty:
            ContentUnavailableView("No cameras", systemImage: "video.slash")
        case .failed:
            ContentUnavailableView(
                "Can't reach the server",
                systemImage: "wifi.slash",
                description: Text("Check your connection settings.")
            )
        case let .ready(cameras, timeline):
            ready(cameras: cameras, timeline: timeline)
        }
    }

    @ViewBuilder
    private func ready(cameras: [Camera], timeline: DayTimeline) -> some View {
        // iPhone landscape is wide but short: a bottom scrubber would eat the scarce height, so put
        // the grid and a vertical scrubber side by side. Everywhere else keeps the bottom card.
        if isCompactHeight {
            sideBySide(cameras: cameras, timeline: timeline)
        } else {
            bottomCard(cameras: cameras, timeline: timeline)
        }
    }

    private func bottomCard(cameras: [Camera], timeline: DayTimeline) -> some View {
        ZStack(alignment: .bottom) {
            grid(cameras: cameras, bottomInset: cardHeight)
            // Float the glass card over the grid so tiles scroll behind it (the glass refracts them).
            // macOS reports regular width too, so it takes `.row` alongside iPad.
            ScrollableTimelineView(
                arrangement: isCompactWidth ? .stack : .row,
                span: viewModel.span, timeline: timeline, clock: viewModel.clock, transport: viewModel.transport
            ) { time in
                viewModel.scrub(to: time)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: { cardHeight = $0 }
        }
    }

    private func sideBySide(cameras: [Camera], timeline: DayTimeline) -> some View {
        // Drive the split from the available size directly: a flexible GeometryReader sibling inside an
        // HStack collapses both panes, so measure once and lay out with explicit widths/heights.
        GeometryReader { geo in
            let cardWidth: CGFloat = 160
            let gap: CGFloat = 12
            let columnWidth = max(0, geo.size.width - cardWidth - gap)
            HStack(spacing: gap) {
                // A single-column scroll, not a grid: each tile fills the column's 16:9 height, so one
                // camera dominates the landscape height and the next peeks below it. No hero: the
                // single column already gives one camera the height.
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(cameras) { camera in
                            cameraTile(camera, style: .regularGrid)
                                .frame(width: columnWidth, height: columnWidth * 9 / 16)
                        }
                    }
                }
                .frame(width: columnWidth)

                // The slim scrubber card takes a fixed strip of width and the full height, flush to
                // the trailing edge.
                ScrollableTimelineView(
                    arrangement: .rail,
                    span: viewModel.span, timeline: timeline, clock: viewModel.clock, transport: viewModel.transport
                ) { time in
                    viewModel.scrub(to: time)
                }
                .frame(width: cardWidth, height: geo.size.height)
            }
        }
        .padding(.leading, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func grid(cameras: [Camera], bottomInset: CGFloat) -> some View {
        if isCompactWidth {
            // Hero + the rest in **one** container over **one** `ForEach`, so a hero flip is a
            // reorder — `Camera.id` keeps each tile's identity, and `ScrubbingPlayerView`/the
            // tile's `.task`s never re-run on the swap (see `HeroGridLayout`).
            let ordered = viewModel.heroOrderedCameras(cameras)
            ScrollView {
                HeroGridLayout(spacing: 12) {
                    ForEach(ordered) { camera in
                        cameraTile(camera, style: camera.name == viewModel.heroCamera?.name ? .hero : .compactGrid)
                    }
                }
                .padding(16)
                .padding(.top, headerHeight)
                .padding(.bottom, bottomInset)
            }
            .auroraTrackingScrollGlass(isGlass: $isHeaderGlass)
        } else if usesFixedColumnGrid {
            // iPad: a fixed 3-column grid — `bestFit` would pick two huge columns for a handful of
            // cameras on an 11" iPad, which the mock does not show.
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 3), spacing: 14) {
                    ForEach(cameras) { camera in cameraTile(camera, style: .regularGrid) }
                }
                .padding(24)
                .padding(.top, headerHeight)
                .padding(.bottom, bottomInset)
            }
            .auroraTrackingScrollGlass(isGlass: $isHeaderGlass)
        } else {
            // macOS: size the tiles to the window — a handful of cameras fills it like a video wall
            // rather than huddling at the adaptive minimum in a corner of a big display (0.3.4).
            GeometryReader { geo in
                let spacing: CGFloat = 12
                let padding: CGFloat = 16
                let available = CGSize(
                    width: max(0, geo.size.width - padding * 2),
                    height: max(0, geo.size.height - headerHeight - bottomInset - padding * 2)
                )
                let layout = TimelineGridLayout.bestFit(
                    tileCount: cameras.count,
                    available: available,
                    spacing: spacing,
                    minimumTileWidth: 220
                )
                ScrollView {
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.fixed(layout.tileWidth), spacing: spacing),
                            count: layout.columnCount
                        ),
                        spacing: spacing
                    ) {
                        ForEach(cameras) { camera in cameraTile(camera, style: .regularGrid) }
                    }
                    // Center the wall in the space above the scrubber card; the fallback
                    // (more cameras than fit) grows past `minHeight` and scrolls as before.
                    .frame(maxWidth: .infinity, minHeight: available.height)
                    .padding(padding)
                    .padding(.top, headerHeight)
                    .padding(.bottom, bottomInset)
                }
                .auroraTrackingScrollGlass(isGlass: $isHeaderGlass)
            }
        }
    }

    private func cameraTile(_ camera: Camera, style: PreviewTileStyle) -> some View {
        PreviewTileView(
            viewModel: tiles.tile(for: camera, make: makeTileViewModel),
            clock: viewModel.clock,
            transport: viewModel.transport,
            range: viewModel.span,
            style: style,
            alertLabel: viewModel.alertLabels[camera.name]
        )
        .onTapGesture {
            // Stop the grid before pushing one camera's player: the tiles stay in the hierarchy
            // behind it, so leaving playback running would keep every stream open under the screen
            // that replaced them.
            viewModel.transport.pause()
            openedRecording = RecordingRoute(camera: camera, instant: viewModel.clock.instant)
        }
    }
}

/// The pushed recordings player: which camera, and the instant the tile was tapped at — the
/// playhead the full-resolution stream opens on.
private struct RecordingRoute: Hashable {
    let camera: Camera
    let instant: Date
}

/// Keeps one tile view model per camera alive across re-renders (so players aren't rebuilt).
@MainActor
private final class TileStore {
    private var tiles: [CameraName: PreviewTileViewModel] = [:]

    func tile(for camera: Camera, make: (Camera) -> PreviewTileViewModel) -> PreviewTileViewModel {
        if let existing = tiles[camera.name] { return existing }
        let created = make(camera)
        tiles[camera.name] = created
        return created
    }
}
