import AVFoundation
import SwiftUI

import CommonPlayer
import TimelineDomain

/// One camera tile, kept in sync with the shared scrub clock.
struct PreviewTileView: View {
    let viewModel: PreviewTileViewModel
    let clock: ScrubClock
    let transport: TimelineTransport
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
            // The first load is keyed off the **fixed span start**, so extending the live edge
            // (which moves only span.end) can't cancel an in-flight first load and strand the tile
            // on its spinner. Following the live edge is a separate trigger keyed off span.end — it
            // refreshes the material in place (newly recorded footage reaches the tile without
            // rebuilding the playing clip) but never tears the first load down.
            .task(id: range.start) {
                await viewModel.prepare(range: range, at: clock.instant)
            }
            .task(id: range.end) {
                await viewModel.followLiveEdge(to: range, at: clock.instant)
            }
            .onChange(of: clock.instant) { _, instant in
                viewModel.scrub(to: instant)
            }
            // Entering playback swaps the low-res scrub material for the camera's own recording;
            // leaving it puts the tile back on the previews at wherever the playhead stopped.
            .task(id: transport.isPlaying) {
                if transport.isPlaying {
                    await viewModel.beginPlayback(at: clock.instant, speed: transport.speed)
                } else {
                    viewModel.endPlayback(at: clock.instant)
                }
            }
            .onChange(of: transport.speed) { _, speed in
                viewModel.select(speed)
            }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.display {
        case .loading:
            ProgressView()
        case .clip(let player), .recording(let player):
            ScrubbingPlayerView(player: player, videoGravity: .resizeAspectFill)
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
