#if os(iOS)
import AVFoundation
#endif
import AVKit
import Observation

/// Owns the live `AVPlayer`, its Picture-in-Picture controller, and the playback state the custom
/// overlay controls bind to. It replaces `AVPlayerViewController`/`AVPlayerView`: the video is
/// rendered by a bare `AVPlayerLayer` host (`LivePlayerView`) so the zoom transform scales only the
/// video, and the transport controls live outside the zoom. Because there is no AVKit chrome, there
/// is no built-in aspect-fill pinch to race the container's gestures either.
///
/// Playback is started from `start()` (the view's `onAppear`), not `init`, and the player is built
/// lazily — so the throwaway instances SwiftUI constructs and discards on every `LiveVideoView`
/// re-init never open a stream or register an observer.
@MainActor
@Observable
public final class LivePlayerModel {
    public private(set) var isPlaying: Bool
    public private(set) var isMuted: Bool
    public private(set) var isPictureInPictureActive: Bool
    public private(set) var isPictureInPicturePossible: Bool

    @ObservationIgnored public private(set) lazy var player: AVPlayer = makeAuthedPlayer(url: url, headers: headers)
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let headers: [String: String]
    @ObservationIgnored private var didStart = false
    // Retained so an active PiP session keeps its source layer alive after the hosting view is torn
    // down (see `PictureInPictureRetainer`).
    @ObservationIgnored private var playerLayer: AVPlayerLayer?
    @ObservationIgnored private var pictureInPictureController: AVPictureInPictureController?
    @ObservationIgnored private var pictureInPictureCoordinator: PictureInPictureCoordinator?
    @ObservationIgnored private var pictureInPicturePossibleObservation: NSKeyValueObservation?
    // Written once during setup, read once in the nonisolated `deinit`; the escape hatch lets deinit
    // unregister the non-Sendable observer token.
    @ObservationIgnored private nonisolated(unsafe) var interruptionObserver: (any NSObjectProtocol)?

    public var isPictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    public init(url: URL, headers: [String: String]) {
        self.url = url
        self.headers = headers
        isPlaying = true
        isMuted = false
        isPictureInPictureActive = false
        isPictureInPicturePossible = false
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    /// Begins playback and interruption handling. Idempotent, and safe to call on the model SwiftUI
    /// keeps — the discarded ones never reach here, so no stream is opened for them.
    public func start() {
        guard !didStart else { return }
        didStart = true
        player.play()
        observeInterruptions()
    }

    /// Wires Picture-in-Picture to the host's layer once it exists. Called from the representable's
    /// `make…View`; re-entrant calls (SwiftUI updates) are ignored so the controller is built once.
    public func attach(playerLayer: AVPlayerLayer) {
        guard pictureInPictureController == nil,
              AVPictureInPictureController.isPictureInPictureSupported(),
              let controller = AVPictureInPictureController(playerLayer: playerLayer) else { return }
        #if os(iOS)
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        #endif
        let coordinator = PictureInPictureCoordinator(model: self)
        controller.delegate = coordinator
        self.playerLayer = playerLayer
        pictureInPictureCoordinator = coordinator
        pictureInPictureController = controller
        pictureInPicturePossibleObservation = controller.observe(
            \.isPictureInPicturePossible,
            options: [.new]
        ) { [weak self] _, change in
            guard let possible = change.newValue else { return }
            Task { @MainActor in self?.isPictureInPicturePossible = possible }
        }
    }

    public func togglePlayPause() {
        isPlaying.toggle()
        if isPlaying { player.play() } else { player.pause() }
    }

    public func toggleMute() {
        player.isMuted.toggle()
        isMuted = player.isMuted
    }

    public func togglePictureInPicture() {
        guard let controller = pictureInPictureController else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    fileprivate func setPictureInPictureActive(_ active: Bool) {
        isPictureInPictureActive = active
        if active {
            PictureInPictureRetainer.retain(self)
        } else {
            PictureInPictureRetainer.release(self)
        }
    }

    /// An audio-session interruption (a call, Siri, another app playing audio) pauses the player and
    /// deactivates our session. A *live* HLS item can't be un-paused: while it sat idle its segments
    /// rolled off the live window, so `play()` has nothing left to show. Recover when the interruption
    /// ends by reactivating the session and swapping in a fresh live item, which snaps playback back
    /// to the live edge. iOS-only — macOS has no `AVAudioSession`.
    private func observeInterruptions() {
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let ended = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .ended
            guard ended else { return }
            MainActor.assumeIsolated { self?.resumeAtLiveEdge() }
        }
        #endif
    }

    private func resumeAtLiveEdge() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        player.replaceCurrentItem(with: makeAuthedPlayerItem(url: url, headers: headers))
        player.play()
        isPlaying = true
    }
}

/// Bridges `AVPictureInPictureControllerDelegate` (an `NSObject`, called back on the main thread)
/// into the `@Observable` model. Holds the model weakly so the model owns the coordinator, not the
/// reverse.
private final class PictureInPictureCoordinator: NSObject, AVPictureInPictureControllerDelegate {
    private weak var model: LivePlayerModel?

    init(model: LivePlayerModel) {
        self.model = model
        super.init()
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        let model = self.model
        MainActor.assumeIsolated { model?.setPictureInPictureActive(true) }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        let model = self.model
        MainActor.assumeIsolated { model?.setPictureInPictureActive(false) }
    }

    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: any Error
    ) {
        let model = self.model
        MainActor.assumeIsolated { model?.setPictureInPictureActive(false) }
    }

    /// "Return to app" from the PiP window: the detail view is still in the navigation stack, so
    /// report the UI as already restored for a seamless hand-back.
    func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

/// Keeps a live model — and thus its `AVPlayer`, `AVPictureInPictureController`, and source layer —
/// alive while its PiP window floats, independent of the SwiftUI view that created it. Once the
/// detail view is popped its `@State` no longer retains the model, but the system requires the app
/// to retain the controller for the session's lifetime; membership is added when PiP starts and
/// removed when it stops or fails.
@MainActor
private enum PictureInPictureRetainer {
    private static var active: [LivePlayerModel] = []

    static func retain(_ model: LivePlayerModel) {
        guard !active.contains(where: { $0 === model }) else { return }
        active.append(model)
    }

    static func release(_ model: LivePlayerModel) {
        active.removeAll { $0 === model }
    }
}
