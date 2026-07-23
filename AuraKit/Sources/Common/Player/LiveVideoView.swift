import SwiftUI

/// The live camera view: an autoplaying stream with pinch-zoom/pan and Picture-in-Picture. Composes
/// the shared `LiveVideoLayout` (video in the zoom, controls fixed outside it) with the live
/// `LivePlayerModel`. Controls auto-hide after a few seconds of no interaction and reappear on a
/// single tap.
public struct LiveVideoView: View {
    @State private var model: LivePlayerModel
    @State private var areControlsVisible = true
    @State private var autoHide: Task<Void, Never>?

    public init(url: URL, headers: [String: String]) {
        _model = State(initialValue: LivePlayerModel(url: url, headers: headers))
    }

    public var body: some View {
        LiveVideoLayout(
            controls: LiveControlBar(
                state: LiveControlState(
                    isPlaying: model.isPlaying,
                    isMuted: model.isMuted,
                    isPictureInPictureSupported: model.isPictureInPictureSupported,
                    isPictureInPictureActive: model.isPictureInPictureActive,
                    isPictureInPicturePossible: model.isPictureInPicturePossible
                ),
                onPlayPause: model.togglePlayPause,
                onMute: model.toggleMute,
                onTogglePictureInPicture: model.togglePictureInPicture,
                onInteract: revealControls
            ),
            areControlsVisible: areControlsVisible,
            onSingleTap: toggleControls
        ) {
            LivePlayerView(model: model)
        }
        .onAppear {
            model.start()
            scheduleAutoHide()
        }
        .onDisappear { autoHide?.cancel() }
    }

    private func toggleControls() {
        if areControlsVisible {
            autoHide?.cancel()
            areControlsVisible = false
        } else {
            revealControls()
        }
    }

    private func revealControls() {
        areControlsVisible = true
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        autoHide?.cancel()
        autoHide = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            areControlsVisible = false
        }
    }
}
