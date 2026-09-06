import SwiftUI

import CommonDesign

/// The transport controls for the live view — play/pause, mute, and Picture-in-Picture — as a
/// floating glass pill. Rendered *outside* the zoom transform, so it stays fixed while the video
/// scales and pans beneath it. A pure function of `LiveControlState` + callbacks; any button press
/// calls `onInteract` so the host can reset its auto-hide timer. The LIVE badge lives in
/// `LiveVideoLayout`, the view that knows where the card is, not here.
public struct LiveControlBar: View {
    private let state: LiveControlState
    private let surface: AuroraGlassSurface
    private let onPlayPause: () -> Void
    private let onMute: () -> Void
    private let onTogglePictureInPicture: () -> Void
    private let onInteract: () -> Void

    public init(
        state: LiveControlState,
        surface: AuroraGlassSurface,
        onPlayPause: @escaping () -> Void,
        onMute: @escaping () -> Void,
        onTogglePictureInPicture: @escaping () -> Void,
        onInteract: @escaping () -> Void
    ) {
        self.state = state
        self.surface = surface
        self.onPlayPause = onPlayPause
        self.onMute = onMute
        self.onTogglePictureInPicture = onTogglePictureInPicture
        self.onInteract = onInteract
    }

    public var body: some View {
        controlCluster
    }

    private var controlCluster: some View {
        HStack(spacing: 28) {
            controlButton(systemImage: state.isPlaying ? "pause.fill" : "play.fill") {
                onPlayPause()
            }
            controlButton(systemImage: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                onMute()
            }
            if state.isPictureInPictureSupported {
                controlButton(
                    systemImage: state.isPictureInPictureActive
                        ? "pip.exit"
                        : "pip.enter"
                ) {
                    onTogglePictureInPicture()
                }
                .disabled(!state.isPictureInPicturePossible && !state.isPictureInPictureActive)
                .opacity(state.isPictureInPicturePossible || state.isPictureInPictureActive ? 1 : 0.4)
                .accessibilityHint("Available once the stream is playing")
            }
        }
        .font(.title2)
        .foregroundStyle(surface == .video ? .white : Color.auroraTextPrimary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .auroraChip(over: surface)
        .shadow(color: .black.opacity(surface == .video ? 0.5 : 0.22), radius: 17, y: 7)
    }

    private func controlButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            onInteract()
            action()
        } label: {
            Image(systemName: systemImage)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
