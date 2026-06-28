import SwiftUI

import EventsDomain

public struct EventsListView: View {
    @State private var viewModel: EventsListViewModel
    private let onOpenSettings: () -> Void
    private let makeDetailViewModel: (Event) -> EventDetailViewModel

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
            content
                .navigationTitle("Events")
                .navigationDestination(for: Event.self) { event in
                    EventDetailView(viewModel: makeDetailViewModel(event))
                }
                .toolbar {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                    }
                }
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .loaded(let events):
            List(events) { event in
                NavigationLink(value: event) {
                    EventRowView(event: event) { await viewModel.thumbnail(for: $0) }
                }
            }
            .refreshable { await viewModel.load() }
        case .empty:
            ContentUnavailableView("No events", systemImage: "bell.slash")
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't load events", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message(for: error))
            } actions: {
                Button("Retry") { Task { await viewModel.load() } }
                Button("Settings", action: onOpenSettings)
            }
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
