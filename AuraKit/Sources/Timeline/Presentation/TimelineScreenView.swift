import SwiftUI

import CamerasDomain
import TimelineDomain

public struct TimelineScreenView: View {
    private let viewModel: TimelineScreenViewModel
    private let makeTileViewModel: (Camera) -> PreviewTileViewModel
    private let onOpenRecording: (Camera, Date) -> Void

    @State private var tiles = TileStore()
    @State private var cardHeight: CGFloat = 180

    public init(
        viewModel: TimelineScreenViewModel,
        makeTileViewModel: @escaping (Camera) -> PreviewTileViewModel,
        onOpenRecording: @escaping (Camera, Date) -> Void
    ) {
        self.viewModel = viewModel
        self.makeTileViewModel = makeTileViewModel
        self.onOpenRecording = onOpenRecording
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Timeline")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        }
        .task { await viewModel.load() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .empty:
            ContentUnavailableView("No cameras", systemImage: "video.slash")
        case .failed:
            ContentUnavailableView(
                "Can't reach the server",
                systemImage: "wifi.slash",
                description: Text("Check your connection settings.")
            )
        case let .ready(cameras, timeline):
            ready(cameras: cameras, timeline: timeline)
        }
    }

    private func ready(cameras: [Camera], timeline: DayTimeline) -> some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                    ForEach(cameras) { camera in
                        PreviewTileView(
                            viewModel: tiles.tile(for: camera, make: makeTileViewModel),
                            clock: viewModel.clock,
                            range: viewModel.span
                        )
                        .onTapGesture { onOpenRecording(camera, viewModel.clock.instant) }
                    }
                }
                .padding()
                .padding(.bottom, cardHeight)
            }
            // Float the glass card over the grid so tiles scroll behind it (the glass refracts them).
            ScrollableTimelineView(span: viewModel.span, timeline: timeline, clock: viewModel.clock) { time in
                viewModel.scrub(to: time)
            }
            .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.height } action: { cardHeight = $0 }
        }
    }
}

/// Keeps one tile view model per camera alive across re-renders (so players aren't rebuilt).
@MainActor
private final class TileStore {
    private var tiles: [CameraName: PreviewTileViewModel] = [:]

    func tile(for camera: Camera, make: (Camera) -> PreviewTileViewModel) -> PreviewTileViewModel {
        if let existing = tiles[camera.name] { return existing }
        let created = make(camera)
        tiles[camera.name] = created
        return created
    }
}
