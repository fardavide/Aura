import SwiftUI

import CamerasDomain
import CommonDesign
import CommonPlayer

public struct CameraDetailView<CameraTimeline: View>: View {
    private let camera: Camera
    private let title: String
    private let cameraTimeline: (Camera) -> CameraTimeline
    @State private var playback: Playback
    @State private var isTimelinePresented = false

    public init(
        camera: Camera,
        viewModel: CameraDetailViewModel,
        @ViewBuilder cameraTimeline: @escaping (Camera) -> CameraTimeline
    ) {
        self.camera = camera
        title = viewModel.title
        self.cameraTimeline = cameraTimeline
        let playback: Playback = switch viewModel.state {
        case .playing(let source):
            .live(LivePlayerModel(url: source.url, headers: source.headers))
        case .unavailable:
            .unavailable
        }
        _playback = State(initialValue: playback)
    }

    public var body: some View {
        content
            .navigationTitle(title)
            .toolbar {
                Button {
                    // The Timeline can start playback before the live view disappears.
                    if case .live(let model) = playback {
                        model.stop()
                    }
                    isTimelinePresented = true
                } label: {
                    Label("Timeline", systemImage: "calendar.day.timeline.left")
                }
                .labelStyle(.iconOnly)
            }
            .navigationDestination(isPresented: $isTimelinePresented) {
                cameraTimeline(camera)
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            #endif
    }

    @ViewBuilder private var content: some View {
        switch playback {
        case .live(let model):
            LiveVideoView(model: model)
        case .unavailable:
            ContentUnavailableView {
                Label {
                    Text("No live stream").auroraText(.headline)
                } icon: {
                    Image(systemName: "video.slash")
                }
            } description: {
                Text("This camera has no go2rtc stream configured.").auroraText(.body)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .auroraBackground()
        }
    }

    private enum Playback {
        case live(LivePlayerModel)
        case unavailable
    }
}
