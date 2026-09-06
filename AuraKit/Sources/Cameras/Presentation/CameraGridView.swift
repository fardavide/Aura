import SwiftUI

import CamerasDomain
import CommonDesign

/// The camera grid, and the stack that pushes one camera's live stream — and, from there, that
/// camera's recordings. The recordings screen belongs to the Timeline vertical, so it arrives as
/// an injected builder rather than as a dependency of this one.
public struct CameraGridView<CameraTimeline: View>: View {
    @State private var viewModel: CameraGridViewModel
    private let onOpenSettings: () -> Void
    private let makeDetailViewModel: (Camera) -> CameraDetailViewModel
    private let cameraTimeline: (Camera) -> CameraTimeline

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    // Pinned outside the wall's ScrollView, so it needs its own measured height to reserve as top
    // spacing and its own scroll-offset tracking to know when to show its glass backing — see
    // `AuroraScrollHeader`'s doc comment for why this is hand-rolled rather than a system toolbar.
    @State private var headerHeight: CGFloat = 0
    @State private var isHeaderGlass = false

    public init(
        viewModel: CameraGridViewModel,
        onOpenSettings: @escaping () -> Void,
        makeDetailViewModel: @escaping (Camera) -> CameraDetailViewModel,
        @ViewBuilder cameraTimeline: @escaping (Camera) -> CameraTimeline
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onOpenSettings = onOpenSettings
        self.makeDetailViewModel = makeDetailViewModel
        self.cameraTimeline = cameraTimeline
    }

    public var body: some View {
        NavigationStack {
            screen
                .auroraBackground()
                .navigationTitle("Cameras")
                .auroraHiddenNavigationBar()
                .navigationDestination(for: Camera.self) { camera in
                    CameraDetailView(camera: camera, viewModel: makeDetailViewModel(camera))
                }
                .navigationDestination(for: CameraTimelineRoute.self) { route in
                    cameraTimeline(route.camera)
                }
        }
        .task {
            await viewModel.load()
            // Keep the stills and activity badges current while the grid is on screen; cancelled
            // automatically when it disappears.
            while !Task.isCancelled {
                try? await Task.sleep(for: refreshInterval)
                await viewModel.refresh()
            }
        }
    }

    private let refreshInterval: Duration = .seconds(2)

    /// The pinned header floats over the scrolling wall (glass fading in once tiles scroll behind
    /// it); the chip rows stay pinned below it, outside the scroll, same as before. Every piece
    /// outside the `switch` in `content`, so the title and the gear render in every state
    /// (`.loading`, `.loaded`, `.empty` and `.failed` alike) — `.empty` in particular has no
    /// actions of its own, so losing the gear there would strand the user with no route to Settings.
    private var screen: some View {
        ZStack(alignment: .top) {
            VStack(alignment: .leading, spacing: verticalSizeClass == .compact ? 8 : 12) {
                Color.clear.frame(height: headerHeight)
                if verticalSizeClass != .compact && viewModel.hasSummaryChips {
                    summaryChips(leadingPadding: contentPadding)
                }
                groupChipsRow
                content
            }
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
        }
    }

    private var header: some View {
        AuroraScrollHeader(isGlass: isHeaderGlass, horizontalPadding: contentPadding) {
            if verticalSizeClass == .compact {
                // The tab bar already names the tab, and a title row + two chip rows would eat too
                // much of a ~390pt-tall window — one row does the header's whole job here.
                if viewModel.hasSummaryChips {
                    summaryChips(leadingPadding: 0)
                } else {
                    Spacer()
                }
            } else {
                Text("Cameras").auroraText(.screenTitle).foregroundStyle(.auroraTextPrimary)
            }
        } trailing: {
            gearButton
        }
    }

    private func summaryChips(leadingPadding: CGFloat) -> some View {
        CameraSummaryChips(
            rightNow: viewModel.rightNow,
            todayChipText: viewModel.todayChipText,
            todayBreakdownText: viewModel.todayBreakdownText,
            freeBytes: viewModel.storage?.freeBytes,
            retentionChipText: viewModel.retentionChipText,
            offlineChipText: viewModel.offlineChipText,
            leadingPadding: leadingPadding
        )
    }

    private var gearButton: some View {
        Button(action: onOpenSettings) {
            Image(systemName: "gearshape")
                .auroraText(.chip)
                .foregroundStyle(.auroraTextPrimary)
                .auroraChip()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    @ViewBuilder private var groupChipsRow: some View {
        if !viewModel.groups.isEmpty {
            GroupChips(
                groups: viewModel.groups,
                selected: viewModel.selectedGroupName,
                onSelect: viewModel.selectGroup,
                leadingPadding: contentPadding
            )
        }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded:
            wallScroller
        case .empty:
            ContentUnavailableView("No cameras", systemImage: "video.slash")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't load cameras", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message(for: error))
            } actions: {
                Button("Retry") { Task { await viewModel.load() } }
                Button("Settings", action: onOpenSettings)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The one `ScrollView` on screen. A group whose cameras are all disabled/hidden shows an empty
    /// state instead of the wall — the group chip must never look like it did nothing. No
    /// `.scrollClipDisabled()`: scrolled tiles must never paint over the pinned header.
    private var wallScroller: some View {
        ScrollView {
            if viewModel.visibleCameras.isEmpty {
                ContentUnavailableView("No cameras in this group", systemImage: "video.slash")
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                wall
                    .padding(.horizontal, contentPadding)
                    .padding(.bottom, 24)
            }
        }
        .auroraTrackingScrollGlass(isGlass: $isHeaderGlass)
        .refreshable { await viewModel.load() }
    }

    /// One `ForEach` inside `CameraWallLayout`, so a hero swap re-proposes a size and flips a style
    /// parameter rather than re-parenting a tile — the tile's decoded-image `@State` survives.
    /// Hero order and hero styling both come from `wallStyle.hasHero`: the compact-height 3-up wall
    /// (no hero) iterates `visibleCameras` in place, so an alert never reshuffles it.
    private var wall: some View {
        CameraWallLayout(style: wallStyle, spacing: 12) {
            ForEach(wallStyle.hasHero ? viewModel.wallCameras : viewModel.visibleCameras) { camera in
                NavigationLink(value: camera) {
                    CameraTileView(
                        camera: camera,
                        activity: viewModel.activity(for: camera),
                        isOffline: viewModel.isOffline(camera),
                        imageData: viewModel.previewImage(for: camera),
                        style: wallStyle.hasHero && camera.id == viewModel.heroCamera?.id ? .hero : .tile
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.smooth(duration: 0.35), value: viewModel.heroCamera)
        .background {
            AuroraGlow()
                .padding(.horizontal, -contentPadding)
                .padding(.vertical, -12)
        }
    }

    /// A full-width vertical list in iPhone portrait (compact width, regular height), with a hero
    /// on top; a uniform 3-up grid in iPhone landscape (compact height), no hero; a 2fr/1fr hero
    /// leading layout on iPad and macOS (regular width).
    private var wallStyle: CameraWallLayout.Style {
        if verticalSizeClass == .compact {
            return .uniform(columns: 3)
        }
        if horizontalSizeClass == .compact {
            return .heroTop
        }
        return .heroLeading
    }

    private var contentPadding: CGFloat {
        horizontalSizeClass == .compact ? 16 : 24
    }

    private func message(for error: CamerasError) -> String {
        switch error {
        case .unreachable: "Can't reach the server. Check the address and your connection."
        case .notAuthorized: "Authentication failed. Check your username and password."
        case .serverUnavailable: "The server returned an error. Try again later."
        case .invalidData: "The server's response couldn't be read."
        case .unknown: "Something went wrong."
        }
    }
}
