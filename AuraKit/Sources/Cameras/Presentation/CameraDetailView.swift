import SwiftUI

public struct CameraDetailView: View {
    private let viewModel: CameraDetailViewModel

    public init(viewModel: CameraDetailViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        content
            .navigationTitle(viewModel.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .playing(let source):
            VideoPlayerView(source: source)
                .background(.black)
                .ignoresSafeArea()
        case .unavailable:
            ContentUnavailableView(
                "No live stream",
                systemImage: "video.slash",
                description: Text("This camera has no go2rtc stream configured.")
            )
        }
    }
}
