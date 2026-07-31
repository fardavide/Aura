import SwiftUI

import CamerasDomain
import CommonPlayer

public struct CameraDetailView: View {
    private let camera: Camera
    private let viewModel: CameraDetailViewModel

    public init(camera: Camera, viewModel: CameraDetailViewModel) {
        self.camera = camera
        self.viewModel = viewModel
    }

    public var body: some View {
        content
            .navigationTitle(viewModel.title)
            .toolbar {
                // Straight from what this camera is showing now to what it recorded — the same
                // screen a Timeline tile opens, without going through the tab and finding the
                // camera again. Offered even when there is no live stream: the recordings are
                // still there. The destination decides the instant, which is the live edge.
                NavigationLink(value: CameraTimelineRoute(camera: camera)) {
                    Label("Timeline", systemImage: "calendar.day.timeline.left")
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            #endif
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .playing(let source):
            LiveVideoView(url: source.url, headers: source.headers)
        case .unavailable:
            ContentUnavailableView(
                "No live stream",
                systemImage: "video.slash",
                description: Text("This camera has no go2rtc stream configured.")
            )
        }
    }
}
