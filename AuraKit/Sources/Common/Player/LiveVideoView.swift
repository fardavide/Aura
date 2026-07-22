import SwiftUI

/// The live camera view: an autoplaying stream with pinch-zoom/pan and Picture-in-Picture. The
/// video is wrapped in `ZoomableContainer` so only it scales and pans; the transport controls are
/// an overlay *outside* that container, so they stay fixed at their normal size. Controls auto-hide
/// after a few seconds of no interaction and reappear on a single tap.
public struct LiveVideoView: View {
    @State private var model: LivePlayerModel
    @State private var areControlsVisible = true
    @State private var autoHide: Task<Void, Never>?

    public init(url: URL, headers: [String: String]) {
        _model = State(initialValue: LivePlayerModel(url: url, headers: headers))
    }

    public var body: some View {
        ZStack {
            ZoomableContainer(onSingleTap: toggleControls) {
                LivePlayerView(model: model)
            }
            LiveControlBar(model: model, onInteract: revealControls)
                .opacity(areControlsVisible ? 1 : 0)
                .allowsHitTesting(areControlsVisible)
                .animation(.easeInOut(duration: 0.2), value: areControlsVisible)
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
