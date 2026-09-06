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
