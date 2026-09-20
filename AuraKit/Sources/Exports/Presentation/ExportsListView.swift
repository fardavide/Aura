import SwiftUI

import CommonDesign
import CommonFiles
import ExportsDomain

/// The Exports tab: the clips Frigate has cut and kept on the server.
///
/// No filter row ships in this release — an export carries a camera, a timestamp and a processing
/// flag, day grouping already answers "when", and "which camera" is legible on every card. A row of
/// chips would cost 44pt off the top of a phone screen, one whole card, to filter a list most
/// people can see in one flick. The header subtitle answers the same question for 17pt and cannot
/// be tapped and disappoint anyone.
public struct ExportsListView: View {
    @State private var viewModel: ExportsListViewModel
    private let downloads: DownloadCenter
    private let onOpenSettings: () -> Void
    private let onOpenTimeline: () -> Void
    private let makePlayerViewModel: (Export) -> ExportPlayerViewModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var path: [Export] = []
    /// The clip filling the detail side. Only meaningful in the side-by-side arrangement; upright,
    /// `path` carries the same choice as a push.
    @State private var selection: Export?
    @State private var headerHeight: CGFloat = 74
    @State private var isHeaderGlass = false
    @State private var pendingSave: FileDestinationRequest?
    @State private var saving: ExportId?

    public init(
        viewModel: ExportsListViewModel,
        downloads: DownloadCenter,
        onOpenSettings: @escaping () -> Void,
        onOpenTimeline: @escaping () -> Void,
        makePlayerViewModel: @escaping (Export) -> ExportPlayerViewModel
    ) {
        _viewModel = State(initialValue: viewModel)
        self.downloads = downloads
        self.onOpenSettings = onOpenSettings
        self.onOpenTimeline = onOpenTimeline
        self.makePlayerViewModel = makePlayerViewModel
    }

    public var body: some View {
        GeometryReader { proxy in
            // Wider than it is tall means there is room for the clip beside the library rather
            // than on top of it: picking one fills the detail side instead of pushing, so the
            // list stays visible. Upright — phone or iPad — keeps the push.
            if proxy.size.width > proxy.size.height {
                splitLayout(canvas: proxy.size)
            } else {
                stackedLayout
            }
        }
        .task { await viewModel.load() }
        // Runs alongside the load and ends itself the moment nothing is being cut.
        .task(id: viewModel.hasProcessingExports) { await viewModel.followProcessingExports() }
        .fileDestination($pendingSave) {
            guard let saving else { return }
            downloads.finishSaving(saving)
            self.saving = nil
        }
        .onChange(of: readyToSave) { _, ready in
            guard let ready, case .readyToSave(let file) = downloads.state(for: ready) else { return }
            saving = ready
            pendingSave = FileDestinationRequest(fileUrl: file.fileUrl, fileName: file.fileName)
        }
    }

    // MARK: Arrangements

    /// Upright: the library fills the screen and a clip pushes over it.
    private var stackedLayout: some View {
        NavigationStack(path: $path) {
            library(isSideBySide: false)
                .navigationDestination(for: Export.self) { player(for: $0) }
        }
    }

    /// On its side: a fixed list column with the chosen clip filling the rest. The list column is
    /// the compact one on a phone; a big window gives it a third of the width so the cards keep
    /// their vertical shape.
    private func splitLayout(canvas: CGSize) -> some View {
        HStack(spacing: 0) {
            library(isSideBySide: true)
                .frame(width: listColumnWidth(canvas: canvas))
            Divider().overlay(.auroraSheetBorder)
            Group {
                if let selection {
                    player(for: selection)
                        // A fresh identity per clip, so the player's pinned view model is rebuilt
                        // for the new file instead of holding the previous one's.
                        .id(selection.id)
                } else {
                    ExportsPlaceholderView(
                        symbol: "play.rectangle",
                        symbolTint: .auroraGradientViolet,
                        title: "Nothing playing",
                        message: "Pick a clip on the left to play it here.",
                        primary: nil,
                        secondary: nil,
                        busy: nil
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .auroraBackground()
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    /// 352pt beside a phone's landscape screen, a third of a big window — never more than half,
    /// which would leave the clip smaller than the list that chose it.
    private func listColumnWidth(canvas: CGSize) -> CGFloat {
        #if os(iOS)
        if horizontalSizeClass == .compact { return min(352, canvas.width * 0.5) }
        #endif
        return min(max(380, canvas.width / 3), canvas.width * 0.5)
    }

    private func player(for export: Export) -> some View {
        ExportPlayerView(
            viewModel: makePlayerViewModel(export),
            cameraName: viewModel.displayName(for: export.camera),
            downloadState: downloads.state(for: export.id),
            onDownload: { downloads.download(export) },
            onCancelDownload: { downloads.cancel(export.id) }
        )
    }

    private func library(isSideBySide: Bool) -> some View {
        ZStack(alignment: .top) {
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: headerHeight)
                        if viewModel.hasStaleContent {
                            ExportsStaleBanner(lastUpdated: viewModel.lastUpdated) {
                                Task { await viewModel.refresh() }
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        content(isSideBySide: isSideBySide)
                    }
                }
                .auroraTrackingScrollGlass(isGlass: $isHeaderGlass)
                .refreshable { await viewModel.refresh() }
                .auroraHiddenNavigationBar()
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation { scroll.scrollTo(target, anchor: .center) }
                }
            }
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
        }
        .auroraBackground()
        .animation(.easeOut(duration: 0.2), value: viewModel.hasStaleContent)
    }

    // MARK: Header

    private var header: some View {
        AuroraScrollHeader(isGlass: isHeaderGlass) {
            VStack(alignment: .leading, spacing: 7) {
                Text(ExportCopy.title)
                    .auroraText(.screenTitle)
                    .foregroundStyle(.auroraTextPrimary)
                    .accessibilityAddTraits(.isHeader)
                // Suppressed on an empty library: "0 clips · 0 cameras" sitting above a panel that
                // already says "No exports yet" reads as a broken count rather than an answer.
                if let summary = viewModel.summary, summary.clipCount > 0 {
                    Text(ExportCopy.summary(summary))
                        .auroraText(.captionEmphasis)
                        .foregroundStyle(.auroraTextSecondary)
                }
            }
        } trailing: {
            HStack(spacing: 8) {
                if downloads.transferringCount > 0 {
                    ExportsDownloadPill(
                        count: downloads.transferringCount,
                        fraction: downloads.overallFraction,
                        scrollToTransfer: {}
                    )
                } else if viewModel.isRefreshing {
                    ExportsUpdatingPill()
                }
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .foregroundStyle(.auroraTextPrimary)
                        .auroraChip()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }
        }
    }

    // MARK: Content

    @ViewBuilder private func content(isSideBySide: Bool) -> some View {
        switch viewModel.state {
        case .loading:
            // No skeleton rows: a tappable ghost is the worst kind of dead control, and there is
            // nothing yet to act on.
            ProgressView().tint(.auroraGradientPink)
                .frame(maxWidth: .infinity, minHeight: 280)
        case .empty:
            ExportsPlaceholderView(
                symbol: "film.stack",
                symbolTint: .auroraGradientViolet,
                title: ExportCopy.emptyTitle,
                message: ExportCopy.emptyBody,
                primary: .init(title: ExportCopy.openTimeline, perform: onOpenTimeline),
                secondary: nil,
                busy: nil
            )
            .frame(minHeight: 420)
        case .failed:
            ExportsPlaceholderView(
                symbol: "antenna.radiowaves.left.and.right.slash",
                symbolTint: .auroraAlertTagText,
                title: ExportCopy.unreachableTitle,
                message: ExportCopy.unreachableBody(server: viewModel.serverLabel),
                primary: .init(title: ExportCopy.tryAgain, perform: { Task { await viewModel.retry() } }),
                secondary: .init(title: ExportCopy.serverSettings, perform: onOpenSettings),
                busy: viewModel.isRetrying
                    ? (title: "Retrying…", reason: ExportCopy.retryingReason(server: viewModel.serverLabel))
                    : nil
            )
            .frame(minHeight: 420)
        case .loaded(let groups):
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(groups) { group in
                    dayGroup(group, isSideBySide: isSideBySide)
                }
            }
            .padding(.horizontal, ExportCardStyle.screenMargin(horizontalSizeClass: isRegularWidth))
            .padding(.bottom, 24)
        }
    }

    private func dayGroup(_ group: ExportDayGroup, isSideBySide: Bool) -> some View {
        VStack(alignment: .leading, spacing: ExportCardStyle.betweenCards) {
            Text(viewModel.dayTitle(for: group))
                .auroraText(.sectionHeading)
                .textCase(.uppercase)
                .foregroundStyle(.auroraTextQuaternary)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 18)
                .padding(.bottom, 2)
            if usesGrid(isSideBySide: isSideBySide) {
                // A wide column holds two vertical cards side by side. One stretched row across a
                // 1366pt window is a dead gap between the name and the controls.
                LazyVGrid(columns: gridColumns, spacing: ExportCardStyle.betweenCards) {
                    ForEach(group.exports) { export in
                        card(export, isSideBySide: isSideBySide)
                    }
                }
            } else {
                ForEach(group.exports) { export in
                    card(export, isSideBySide: isSideBySide)
                }
            }
        }
        .animation(.auroraHeroSwap, value: group.exports)
    }

    private func card(_ export: Export, isSideBySide: Bool) -> some View {
        ExportCardView(
            export: export,
            layout: cardLayout(isSideBySide: isSideBySide),
            cameraName: viewModel.displayName(for: export.camera),
            downloadState: downloads.state(for: export.id),
            loadThumbnail: viewModel.thumbnail,
            onPlay: { play(export, isSideBySide: isSideBySide) },
            onDownload: { downloads.download(export) },
            onCancelDownload: { downloads.cancel(export.id) }
        )
        .id(export.id)
        .transition(.opacity)
    }

    /// Side by side the clip fills the detail column; upright it pushes. One verb either way, so
    /// the card never has to know which arrangement it is in.
    private func play(_ export: Export, isSideBySide: Bool) {
        if isSideBySide {
            selection = export
        } else {
            path.append(export)
        }
    }

    private func cardLayout(isSideBySide: Bool) -> ExportCardView.Layout {
        if isRegularWidth { return .stacked }
        return isSideBySide ? .compactRow : .row
    }

    /// Two-up only when the library has the whole screen. In the side-by-side arrangement the
    /// library is a column, and two cards across it would be narrower than their own thumbnails.
    private func usesGrid(isSideBySide: Bool) -> Bool {
        isRegularWidth && !isSideBySide
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: ExportCardStyle.betweenCards),
            GridItem(.flexible(), spacing: ExportCardStyle.betweenCards),
        ]
    }

    private var isRegularWidth: Bool {
        #if os(macOS)
        return true
        #else
        return horizontalSizeClass == .regular
        #endif
    }

    /// The first export whose bytes have landed and are waiting for a destination.
    private var readyToSave: ExportId? {
        viewModel.groups.flatMap(\.exports).first { export in
            if case .readyToSave = downloads.state(for: export.id) { return true }
            return false
        }?.id
    }

    /// The transferring card the header pill scrolls to.
    private var scrollTarget: ExportId? {
        viewModel.groups.flatMap(\.exports).first { downloads.state(for: $0.id)?.isTransferring == true }?.id
    }
}
