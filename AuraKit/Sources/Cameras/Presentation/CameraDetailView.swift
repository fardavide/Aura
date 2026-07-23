import SwiftUI

import CommonPlayer

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
