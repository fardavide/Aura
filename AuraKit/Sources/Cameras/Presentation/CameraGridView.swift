import SwiftUI

import CamerasDomain

public struct CameraGridView: View {
    @State private var viewModel: CameraGridViewModel
    private let onOpenSettings: () -> Void
    private let makeDetailViewModel: (Camera) -> CameraDetailViewModel

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    public init(
        viewModel: CameraGridViewModel,
        onOpenSettings: @escaping () -> Void,
        makeDetailViewModel: @escaping (Camera) -> CameraDetailViewModel
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onOpenSettings = onOpenSettings
        self.makeDetailViewModel = makeDetailViewModel
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Cameras")
                .navigationDestination(for: Camera.self) { camera in
                    CameraDetailView(viewModel: makeDetailViewModel(camera))
                }
                .toolbar {
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape")
                    }
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

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .loaded:
            ScrollView {
                VStack(spacing: 14) {
                    header
                    SummaryCard(
                        rightNow: viewModel.rightNow,
                        todayEvents: viewModel.todayEvents,
                        storage: viewModel.storage
                    )
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(viewModel.visibleCameras) { camera in
                            NavigationLink(value: camera) {
                                CameraTileView(
                                    camera: camera,
                                    activity: viewModel.activity(for: camera),
                                    isOffline: viewModel.isOffline(camera),
                                    imageData: viewModel.previewImage(for: camera)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .refreshable { await viewModel.load() }
        case .empty:
            ContentUnavailableView("No cameras", systemImage: "video.slash")
        case .failed(let error):
            ContentUnavailableView {
                Label("Couldn't load cameras", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message(for: error))
            } actions: {
                Button("Retry") { Task { await viewModel.load() } }
                Button("Settings", action: onOpenSettings)
            }
        }
    }

    /// A full-width vertical list in iPhone portrait (compact width, regular height); a uniform
    /// 3-up grid in iPhone landscape (compact height); a width-adaptive grid on iPad and macOS.
    private var columns: [GridItem] {
        if verticalSizeClass == .compact {
            return Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
        }
        if horizontalSizeClass == .compact {
            return [GridItem(.flexible())]
        }
        return [GridItem(.adaptive(minimum: 300), spacing: 12)]
    }

    /// The chips row (only when the server defines groups) with the live/offline count pinned at the
    /// trailing edge so it stays put while the chips scroll.
    private var header: some View {
        HStack(spacing: 8) {
            if viewModel.groups.isEmpty {
                Spacer()
            } else {
                GroupChips(
                    groups: viewModel.groups,
                    selected: viewModel.selectedGroupName,
                    onSelect: viewModel.selectGroup
                )
            }
            liveCountPill
                .padding(.leading, viewModel.groups.isEmpty ? 0 : 4)
                .padding(.trailing)
        }
        .padding(.top, 4)
    }

    private var liveCountPill: some View {
        HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 7, height: 7)
            Text(countLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(.thinMaterial, in: Capsule())
    }

    private var countLabel: String {
        let live = "\(viewModel.liveCount) live"
        guard viewModel.offlineCount > 0 else { return live }
        return "\(live) · \(viewModel.offlineCount) offline"
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
