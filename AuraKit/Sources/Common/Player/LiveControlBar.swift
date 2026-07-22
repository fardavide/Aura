import SwiftUI

/// The transport controls for the live view — play/pause, mute, and Picture-in-Picture — plus a
/// LIVE badge. Rendered as an overlay *outside* the zoom transform, so it stays fixed while the
/// video scales and pans beneath it. Any button press calls `onInteract` so the host can reset its
/// auto-hide timer.
struct LiveControlBar: View {
    let model: LivePlayerModel
    let onInteract: () -> Void

    var body: some View {
        VStack {
            HStack {
                liveBadge
                Spacer()
            }
            Spacer()
            controlCluster
        }
        .padding(20)
        .foregroundStyle(.white)
    }

    private var liveBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text("LIVE")
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
        .allowsHitTesting(false)
    }

    private var controlCluster: some View {
        HStack(spacing: 28) {
            controlButton(systemImage: model.isPlaying ? "pause.fill" : "play.fill") {
                model.togglePlayPause()
            }
            controlButton(systemImage: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                model.toggleMute()
            }
            if model.isPictureInPictureSupported {
                controlButton(
                    systemImage: model.isPictureInPictureActive
                        ? "pip.exit"
                        : "pip.enter"
                ) {
                    model.togglePictureInPicture()
                }
                .disabled(!model.isPictureInPicturePossible && !model.isPictureInPictureActive)
            }
        }
        .font(.title2)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .glassEffect(.regular, in: Capsule())
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
