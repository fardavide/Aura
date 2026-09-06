import SwiftUI

import CommonDesign
import EventsDomain

public struct EventsListView: View {
    @State private var viewModel: EventsListViewModel
    private let onOpenSettings: () -> Void
    private let makeDetailViewModel: (Event) -> EventDetailViewModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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
            ScrollView {
                LazyVStack(spacing: 0) {
                    header
                    EventFilterChips(filters: viewModel.filters, selection: viewModel.filter, onSelect: viewModel.select)
                        .padding(.vertical, 12)
                    content
                }
            }
            .refreshable { await viewModel.load() }
            .auroraBackground()
            .auroraHiddenNavigationBar()
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Events").auroraText(.screenTitle).foregroundStyle(.auroraTextPrimary)
                if let subtitle = viewModel.summaryText(maximumLabels: maximumSubtitleLabels) {
                    Text(subtitle).auroraText(.captionEmphasis).foregroundStyle(.auroraTextSecondary)
                }
            }
            Spacer(minLength: 8)
            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .foregroundStyle(.auroraTextPrimary)
                    .auroraChip()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
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
