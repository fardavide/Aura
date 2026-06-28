import SwiftUI

import CamerasDomain

public struct CameraGridView: View {
    @State private var viewModel: CameraGridViewModel
    private let onOpenSettings: () -> Void
    private let makeDetailViewModel: (Camera) -> CameraDetailViewModel

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
        .task { await viewModel.load() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .loaded(let cameras):
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(cameras) { camera in
                        NavigationLink(value: camera) {
                            CameraTileView(camera: camera) { await viewModel.previewImage(for: $0) }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
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
