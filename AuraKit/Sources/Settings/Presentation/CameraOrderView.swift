import SwiftUI

import CamerasDomain

/// Drag-to-reorder list of the cameras; every move is saved immediately, so any
/// visible camera list re-sorts live.
public struct CameraOrderView: View {
    @State private var viewModel: CameraOrderViewModel

    public init(viewModel: CameraOrderViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .loading:
                ProgressView()
            case let .loaded(cameras):
                List {
                    ForEach(cameras) { camera in
                        Text(camera.friendlyName ?? camera.name.value)
                    }
                    .onMove { viewModel.move(fromOffsets: $0, toOffset: $1) }
                }
                #if os(iOS)
                .environment(\.editMode, .constant(.active))
                #endif
            case .failed:
                ContentUnavailableView(
                    "Couldn't load cameras",
                    systemImage: "video.slash",
                    description: Text("Check the server connection and try again.")
                )
            }
        }
        .navigationTitle("Camera Order")
        .task { await viewModel.load() }
    }
}
