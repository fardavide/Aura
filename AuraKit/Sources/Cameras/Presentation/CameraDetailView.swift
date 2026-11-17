import SwiftUI

import CamerasDomain
import CommonDesign
import CommonPlayer

public struct CameraDetailView<CameraTimeline: View>: View {
    private let cameras: [Camera]
    private let preview: (Camera) -> Image?
    private let makeViewModel: (Camera) -> CameraDetailViewModel
    private let cameraTimeline: (Camera) -> CameraTimeline
    @State private var camera: Camera
    @State private var playback: Playback
    @State private var isTimelinePresented = false

    public init(
        camera: Camera,
        cameras: [Camera],
        preview: @escaping (Camera) -> Image?,
        makeViewModel: @escaping (Camera) -> CameraDetailViewModel,
        @ViewBuilder cameraTimeline: @escaping (Camera) -> CameraTimeline
    ) {
        self.cameras = cameras
        self.preview = preview
        self.makeViewModel = makeViewModel
        self.cameraTimeline = cameraTimeline
        _camera = State(initialValue: camera)
        _playback = State(initialValue: Playback(state: makeViewModel(camera).state))
    }

    public var body: some View {
        content
            .id(camera.id)
            .navigationTitle(camera.friendlyName ?? camera.name.value)
            .toolbar {
                if cameras.count > 1 {
                    ToolbarItem(placement: .principal) {
                        AuroraPreviewMenu(
                            selected: camera,
                            options: cameras,
                            name: { $0.friendlyName ?? $0.name.value },
                            captureContext: { () },
                            caption: { _ in Text("Live") },
                            loadPreview: { camera, _ in preview(camera) },
                            onSelect: { next, _ in
                                if case .live(let model) = playback { model.stop() }
                                playback = Playback(state: makeViewModel(next).state)
                                camera = next
                            }
                        )
                    }
                }
                ToolbarItem {
                    Button {
                        // The Timeline can start playback before the live view disappears.
                        if case .live(let model) = playback { model.stop() }
                        isTimelinePresented = true
                    } label: {
                        Label("Timeline", systemImage: "calendar.day.timeline.left")
                    }
                    .labelStyle(.iconOnly)
                }
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

        @MainActor init(state: CameraDetailViewModel.State) {
            self = switch state {
            case .playing(let source):
                .live(LivePlayerModel(url: source.url, headers: source.headers))
            case .unavailable:
                .unavailable
            }
        }
    }
}
