import AVKit
import Foundation
import SwiftUI

public struct EventDetailView: View {
    private let viewModel: EventDetailViewModel

    public init(viewModel: EventDetailViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        content
            .navigationTitle(viewModel.title.capitalized)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            #endif
            .task { await viewModel.load() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.state {
        case .unavailable:
            ContentUnavailableView(
                "No clip",
                systemImage: "film.stack",
                description: Text("This event has no recorded clip.")
            )
        case .loading:
            ProgressView()
        case .ready(let data):
            ClipPlayer(data: data)
        case .failed:
            ContentUnavailableView(
                "Couldn't load clip",
                systemImage: "exclamationmark.triangle",
                description: Text("The recording couldn't be downloaded from the server.")
            )
        }
    }
}

/// Writes the downloaded clip bytes to a temp file and plays it locally — avoids streaming the
/// MP4 (and its auth/byte-range pitfalls) through AVPlayer.
private struct ClipPlayer: View {
    let data: Data

    @State private var player: AVPlayer?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player).ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .task {
            guard player == nil else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("mp4")
            guard (try? data.write(to: url)) != nil else { return }
            let created = AVPlayer(url: url)
            player = created
            created.play()
        }
        .onDisappear { player?.pause() }
    }
}
