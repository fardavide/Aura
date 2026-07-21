import SwiftUI

import CamerasDomain
import CamerasEntities
import TimelineDomain

public struct TimelineScreenView: View {
    private let viewModel: TimelineScreenViewModel
    private let makeTileViewModel: (Camera) -> PreviewTileViewModel
    private let onOpenRecording: (Camera, Date) -> Void

    @State private var tiles = TileStore()
    @State private var cardHeight: CGFloat = 180
    @Environment(\.scenePhase) private var scenePhase

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

    public init(
        viewModel: TimelineScreenViewModel,
        makeTileViewModel: @escaping (Camera) -> PreviewTileViewModel,
        onOpenRecording: @escaping (Camera, Date) -> Void
    ) {
        self.viewModel = viewModel
        self.makeTileViewModel = makeTileViewModel
        self.onOpenRecording = onOpenRecording
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Timeline")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                // iPhone landscape is wide but short — reclaim the title bar's height for the grid and
                // the tall scrubber (the tab bar already shows you're on Timeline).
                .toolbar(isCompactHeight ? .hidden : .visible, for: .navigationBar)
                #endif
        }
        .task { await viewModel.loadIfNeeded() }
        .task { await viewModel.autoRefresh() }
        // Returning from the background catches up right away instead of waiting for the next
        // tick — the app may have been suspended for hours, leaving the whole screen at the old
        // live edge. Same gate as the periodic tick: never disturbs a scrub or history browsing.
        .task(id: scenePhase) {
            guard scenePhase == .active, viewModel.shouldRefreshNow else { return }
            await viewModel.refresh()
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
            ScrollableTimelineView(axis: .horizontal, span: viewModel.span, timeline: timeline, clock: viewModel.clock) { time in
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
                // camera dominates the landscape height and the next peeks below it.
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(cameras) { camera in
                            cameraTile(camera)
                                .frame(width: columnWidth, height: columnWidth * 9 / 16)
                        }
                    }
                }
                .frame(width: columnWidth)

                // The slim scrubber card takes a fixed strip of width and the full height.
                ScrollableTimelineView(axis: .vertical, span: viewModel.span, timeline: timeline, clock: viewModel.clock) { time in
                    viewModel.scrub(to: time)
                }
                .frame(width: cardWidth, height: geo.size.height)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func grid(cameras: [Camera], bottomInset: CGFloat) -> some View {
        // iPhone portrait keeps the familiar full-width scrolling column. Regular widths (iPad,
        // macOS) size the tiles to the window instead — a handful of cameras fills it like a
        // video wall rather than huddling at the adaptive minimum in a corner of a big display.
        if isCompactWidth {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(cameras) { camera in cameraTile(camera) }
                }
                .padding()
                .padding(.bottom, bottomInset)
            }
        } else {
            GeometryReader { geo in
                let spacing: CGFloat = 12
                let padding: CGFloat = 16
                let available = CGSize(
                    width: max(0, geo.size.width - padding * 2),
                    height: max(0, geo.size.height - bottomInset - padding * 2)
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
                        ForEach(cameras) { camera in cameraTile(camera) }
                    }
                    // Center the wall in the space above the scrubber card; the fallback
                    // (more cameras than fit) grows past `minHeight` and scrolls as before.
                    .frame(maxWidth: .infinity, minHeight: available.height)
                    .padding(padding)
                    .padding(.bottom, bottomInset)
                }
            }
        }
    }

    private func cameraTile(_ camera: Camera) -> some View {
        PreviewTileView(
            viewModel: tiles.tile(for: camera, make: makeTileViewModel),
            clock: viewModel.clock,
            range: viewModel.span
        )
        .onTapGesture { onOpenRecording(camera, viewModel.clock.instant) }
    }
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
