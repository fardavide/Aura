import SwiftUI

import CommonPlayer
import TimelineDomain

/// One camera tile, kept in sync with the shared scrub clock.
struct PreviewTileView: View {
    let viewModel: PreviewTileViewModel
    let clock: ScrubClock
    let range: TimeRange

    var body: some View {
        // The 16:9 canvas comes from the always-flexible color, not from `content`: a fixed-size
        // placeholder (spinner, no-footage symbol) under `aspectRatio` would collapse the whole
        // tile to its own height, leaving a thin bar where a camera slot belongs.
        Color.black
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottomLeading) {
                Text(viewModel.camera.friendlyName ?? viewModel.camera.name.value)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(8)
            }
            // Keyed off the whole range: the timeline refresh growing the live edge re-runs the
            // prepare, which refreshes the material in place — newly recorded footage reaches the
            // tile without rebuilding the playing clip.
            .task(id: range) {
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
