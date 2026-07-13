import SwiftUI

import CommonPlayer
import TimelineDomain

/// One camera tile, kept in sync with the shared scrub clock.
struct PreviewTileView: View {
    let viewModel: PreviewTileViewModel
    let clock: ScrubClock
    let range: TimeRange

    var body: some View {
        content
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .background(.black)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomLeading) {
                Text(viewModel.camera.friendlyName ?? viewModel.camera.name.value)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(8)
            }
            .task(id: range.start) {
                await viewModel.prepare(range: range, at: clock.instant)
            }
            .onChange(of: clock.instant) { _, instant in
                viewModel.scrub(to: instant)
            }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.display {
        case .loading:
            ProgressView()
        case .clip(let player):
            ScrubbingPlayerView(player: player)
        case .frame(let image):
            image
                .resizable()
                .scaledToFill()
        case .unavailable:
            Image(systemName: "clock.badge.questionmark").foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
        }
    }
}
