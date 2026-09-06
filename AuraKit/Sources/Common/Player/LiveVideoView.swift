import SwiftUI

/// The live camera view: an autoplaying stream with pinch-zoom/pan and Picture-in-Picture. Composes
/// the shared `LiveVideoLayout` (video in the zoom, controls fixed outside it) with the live
/// `LivePlayerModel`. In `.fill` (compact height) the controls auto-hide after a few seconds of no
/// interaction and reappear on a single tap; in `.card` they float below the picture and are
/// always visible (`LiveVideoArrangement.autoHidesControls`).
public struct LiveVideoView: View {
    @State private var model: LivePlayerModel
    @State private var autoHideState = true
    @State private var autoHide: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    public init(url: URL, headers: [String: String]) {
        _model = State(initialValue: LivePlayerModel(url: url, headers: headers))
    }

    private var arrangement: LiveVideoArrangement {
        LiveVideoArrangement(verticalSizeClass: verticalSizeClass)
    }

    private var areControlsVisible: Bool {
        arrangement.autoHidesControls ? autoHideState : true
    }

    public var body: some View {
        LiveVideoLayout(
            arrangement: arrangement,
            controls: LiveControlBar(
                state: LiveControlState(
                    isPlaying: model.isPlaying,
                    isMuted: model.isMuted,
                    isPictureInPictureSupported: model.isPictureInPictureSupported,
                    isPictureInPictureActive: model.isPictureInPictureActive,
                    isPictureInPicturePossible: model.isPictureInPicturePossible
                ),
                surface: arrangement.controlSurface,
                onPlayPause: model.togglePlayPause,
                onMute: model.toggleMute,
                onTogglePictureInPicture: model.togglePictureInPicture,
                onInteract: revealControls
            ),
            areControlsVisible: areControlsVisible,
            onSingleTap: arrangement.autoHidesControls ? toggleControls : {}
        ) {
            LivePlayerView(model: model)
        }
        .onAppear {
            model.start()
            scheduleAutoHide()
        }
        .onDisappear { autoHide?.cancel() }
        // The stream goes stale while the app is away and `onAppear` doesn't re-fire on the way
        // back, so nothing else would restart it.
        .onChange(of: scenePhase) { _, phase in model.handleScenePhase(phase) }
        // Each arrangement starts from a known state: without this, rotating into `.fill` never
        // arms the 3 s timer (it fires from `onAppear` only) and a stale `false` from a previous
        // landscape session would hide the chrome on arrival.
        .onChange(of: arrangement) { _, new in
            autoHideState = true
            if new.autoHidesControls {
                scheduleAutoHide()
            } else {
                autoHide?.cancel()
            }
        }
    }

    private func toggleControls() {
        guard arrangement.autoHidesControls else { return }
        if autoHideState {
            autoHide?.cancel()
            autoHideState = false
        } else {
            revealControls()
        }
    }

    private func revealControls() {
        guard arrangement.autoHidesControls else { return }
        autoHideState = true
        scheduleAutoHide()
    }

    private func scheduleAutoHide() {
        guard arrangement.autoHidesControls else { return }
        autoHide?.cancel()
        autoHide = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            autoHideState = false
        }
    }
}
