import SwiftUI

import CamerasDomain
import CommonDesign

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
            case let .loaded(cameras) where cameras.isEmpty:
                ContentUnavailableView(
                    "No cameras",
                    systemImage: "video.slash",
                    description: Text("This server has no enabled cameras to order.")
                )
            case let .loaded(cameras):
                List {
                    ForEach(cameras) { camera in
                        Text(camera.friendlyName ?? camera.name.value)
                            .auroraText(.body)
                            .foregroundStyle(.auroraTextPrimary)
                    }
                    .onMove { viewModel.move(fromOffsets: $0, toOffset: $1) }
                    .listRowBackground(Color.auroraSettingsRow)
                }
                #if os(iOS)
                .environment(\.editMode, .constant(.active))
                #endif
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't load cameras", systemImage: "video.slash")
                } description: {
                    Text("Check the server connection and try again.")
                } actions: {
                    Button("Retry") {
                        Task { await viewModel.load() }
                    }
                    .buttonStyle(.auroraGradient)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.auroraSettingsSheet)
        .navigationTitle("Camera Order")
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Camera Order").auroraText(.headline)
            }
        }
        .task { await viewModel.load() }
    }
}
