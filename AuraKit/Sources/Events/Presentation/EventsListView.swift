import SwiftUI

import CommonDesign
import EventsDomain

public struct EventsListView: View {
    @State private var viewModel: EventsListViewModel
    private let onOpenSettings: () -> Void
    private let makeDetailViewModel: (Event) -> EventDetailViewModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    // Pinned outside the ScrollView (below), so it needs its own measured height to reserve as
    // top padding for the scrolling content, and its own scroll-offset tracking to know when to
    // show its glass backing — see `AuroraScrollHeader`'s doc comment for why this is hand-rolled
    // rather than a system toolbar title.
    @State private var headerHeight: CGFloat = 74
    @State private var isHeaderGlass = false

    public init(
        viewModel: EventsListViewModel,
        onOpenSettings: @escaping () -> Void,
        makeDetailViewModel: @escaping (Event) -> EventDetailViewModel
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onOpenSettings = onOpenSettings
        self.makeDetailViewModel = makeDetailViewModel
    }

    public var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: headerHeight)
                        EventFilterChips(filters: viewModel.filters, selection: viewModel.filter, onSelect: viewModel.select)
                            .padding(.vertical, 12)
                        content
                        // A direct child of the LazyVStack rather than part of `content`, so it is
                        // only built once the list has been scrolled near its end — that is what
                        // makes it a scroll trigger instead of an eager "fetch all of history".
                        olderEventsFooter
                    }
                }
                .auroraTrackingScrollGlass(isGlass: $isHeaderGlass)
                .refreshable { await viewModel.load() }
                .auroraHiddenNavigationBar()

                header
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            }
            .auroraBackground()
            .navigationDestination(for: Event.self) { event in
                EventDetailView(
                    viewModel: makeDetailViewModel(event),
                    cameraName: viewModel.displayName(for: event.camera)
                )
            }
        }
        .task { await viewModel.load() }
    }

    private var header: some View {
        AuroraScrollHeader(isGlass: isHeaderGlass) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Events").auroraText(.screenTitle).foregroundStyle(.auroraTextPrimary)
                if let subtitle = viewModel.summaryText(maximumLabels: maximumSubtitleLabels) {
                    Text(subtitle).auroraText(.captionEmphasis).foregroundStyle(.auroraTextSecondary)
                }
            }
        } trailing: {
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.auroraTextPrimary)
                    .auroraChip()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
    }

    private var maximumSubtitleLabels: Int? {
        horizontalSizeClass == .compact ? 2 : nil
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView().tint(.auroraGradientPink)
                .frame(maxWidth: .infinity, minHeight: 280)
        case .loaded:
            VStack(spacing: 0) {
                if let hero = viewModel.hero {
                    EventHeroCard(
                        event: hero,
                        cameraName: viewModel.displayName(for: hero.camera),
                        duration: viewModel.durationText(for: hero),
                        loadImage: { await viewModel.heroImage(for: $0) }
                    )
                    .padding(.bottom, 8)
                }
                ForEach(viewModel.groups) { group in
                    EventHourGroupView(
                        group: group,
                        countText: viewModel.countText(for: group),
                        dayContext: viewModel.dayContext,
                        displayName: viewModel.displayName,
                        duration: { viewModel.durationText(for: $0) },
                        loadThumbnail: { await viewModel.thumbnail(for: $0) }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        case .empty:
            ContentUnavailableView("No events", systemImage: "bell.slash")
                .frame(maxWidth: .infinity, minHeight: 280)
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't load events", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message(for: error))
            } actions: {
                Button("Retry") { Task { await viewModel.load() } }
                    .buttonStyle(.auroraGradient)
                Button("Settings", action: onOpenSettings)
                    .buttonStyle(.plain)
                    .auroraChip()
            }
            .frame(maxWidth: .infinity, minHeight: 280)
        }
    }

    /// Paging is orthogonal to `state`: the loaded list stays on screen while an older page loads,
    /// and a failed page costs the footer, never the content. Nothing is drawn once the server has
    /// no older events — the list simply ends.
    @ViewBuilder private var olderEventsFooter: some View {
        switch viewModel.paging {
        case .ready, .loading:
            ProgressView()
                .tint(.auroraGradientPink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .accessibilityLabel("Loading older events")
                // Keyed on the loaded count so a page that lands re-arms the trigger while the
                // footer is still on screen, and paging stops the moment it scrolls out of view.
                .task(id: viewModel.loadedCount) { await viewModel.loadMore() }
        case .failed:
            VStack(spacing: 10) {
                Text("Couldn't load older events")
                    .auroraText(.caption)
                    .foregroundStyle(.auroraTextSecondary)
                Button("Try again") { Task { await viewModel.loadMore() } }
                    .buttonStyle(.plain)
                    .auroraChip()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        case .exhausted:
            EmptyView()
        }
    }

    private func message(for error: EventsError) -> String {
        switch error {
        case .unreachable: "Can't reach the server. Check the address and your connection."
        case .notAuthorized: "Authentication failed. Check your username and password."
        case .serverUnavailable: "The server returned an error. Try again later."
        case .invalidData: "The server's response couldn't be read."
        case .unknown: "Something went wrong."
        }
    }
}
