import AVFoundation
import SwiftUI

import CommonPlayer

/// Full-resolution playback of one camera's recordings, with the transport floated over the video
/// on a glass bar: the instant under the playhead, skip and play/pause, and the speed ladder.
public struct RecordingPlayerView: View {
    // @State-pinned like the sibling screens: the composition root builds a fresh view model on
    // every re-evaluation, and the `.task` below binds only on appearance — a plain `let` would
    // leave the displayed model waiting on a load that ran against a discarded one.
    @State private var viewModel: RecordingPlayerViewModel

    public init(viewModel: RecordingPlayerViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) { transport }
            .navigationTitle(viewModel.camera.friendlyName ?? viewModel.camera.name.value)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            #endif
            .task { await viewModel.loadIfNeeded() }
    }

    @ViewBuilder private var content: some View {
        switch viewModel.display {
        case .loading:
            ProgressView()
        case .ready(let player):
            // Letterboxed, not filled: the point of this screen is the whole recorded frame.
            ScrubbingPlayerView(player: player, videoGravity: .resizeAspect)
                .background(.black)
        case .noFootage:
            ContentUnavailableView(
                "No recording",
                systemImage: "clock.badge.questionmark",
                description: Text("Nothing was recorded in this hour.")
            )
        case .failed:
            ContentUnavailableView(
                "Can't reach the server",
                systemImage: "wifi.slash",
                description: Text("Check your connection settings.")
            )
        }
    }

    /// Shown over playable states only — there is nothing to transport while the first load is in
    /// flight or the server is unreachable, and an empty hour still needs the skip out of it.
    @ViewBuilder private var transport: some View {
        switch viewModel.display {
        case .loading, .failed:
            EmptyView()
        case .ready:
            controls(isPlayable: true)
        // An empty hour has nothing to start, but the skips must stay live so it can be left.
        case .noFootage:
            controls(isPlayable: false)
        }
    }

    private func controls(isPlayable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                clock
                Spacer()
                if !viewModel.hasFootage {
                    Label("No footage", systemImage: "clock.badge.questionmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.thinMaterial, in: Capsule())
                }
            }
            HStack(spacing: 12) {
                skipButton(by: -10, systemImage: "gobackward.10")
                playPauseButton.disabled(!isPlayable)
                skipButton(by: 10, systemImage: "goforward.10")
                Spacer(minLength: 8)
                speedPicker.disabled(!isPlayable)
            }
        }
        .padding(16)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var clock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(viewModel.instant, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            // Seconds are shown because the skip buttons move in ten of them.
            Text(viewModel.instant, format: .dateTime.hour().minute().second())
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
    }

    private var playPauseButton: some View {
        Button {
            viewModel.togglePlayPause()
        } label: {
            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel(viewModel.isPlaying ? "Pause" : "Play")
    }

    private func skipButton(by seconds: TimeInterval, systemImage: String) -> some View {
        Button {
            Task { await viewModel.skip(by: seconds) }
        } label: {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 26, height: 26)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
    }

    private var speedPicker: some View {
        Picker(
            "Speed",
            selection: Binding(get: { viewModel.speed }, set: { viewModel.select($0) })
        ) {
            ForEach(PlaybackSpeed.allCases, id: \.self) { speed in
                Text(speed.title).tag(speed)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 180)
    }
}
