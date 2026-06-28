import SwiftUI

import CamerasDomain
import TimelineDomain

public struct TimelineScreenView: View {
    private let viewModel: TimelineScreenViewModel
    private let makeTileViewModel: (Camera) -> PreviewTileViewModel
    private let onOpenRecording: (Camera, Date) -> Void

    @State private var tiles = TileStore()

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
        VStack(spacing: 12) {
            DayPickerView(day: viewModel.day) { date in
                Task { await viewModel.selectDay(date) }
            }
            DayTimelineView(day: viewModel.day, timeline: timeline, clock: viewModel.clock) { time in
                viewModel.scrub(to: time)
            }
            .padding(.horizontal)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(cameras) { camera in
                        PreviewTileView(
                            viewModel: tiles.tile(for: camera, make: makeTileViewModel),
                            clock: viewModel.clock,
                            range: viewModel.day
                        )
                        .onTapGesture { onOpenRecording(camera, viewModel.clock.instant) }
                    }
                }
                .padding(.horizontal)
            }
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
