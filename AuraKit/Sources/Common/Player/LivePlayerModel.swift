#if os(iOS)
import AVFoundation
#endif
import AVKit
import Observation
import SwiftUI

/// Owns the live `AVPlayer`, its Picture-in-Picture controller, and the playback state the custom
/// overlay controls bind to. It replaces `AVPlayerViewController`/`AVPlayerView`: the video is
/// rendered by a bare `AVPlayerLayer` host (`LivePlayerView`) so the zoom transform scales only the
/// video, and the transport controls live outside the zoom. Because there is no AVKit chrome, there
/// is no built-in aspect-fill pinch to race the container's gestures either.
///
/// Playback is started from `start()` (the view's `onAppear`), not `init`, and the player is built
/// lazily — so the throwaway instances SwiftUI constructs and discards on every `LiveVideoView`
/// re-init never open a stream or register an observer.
///
/// Anything that can leave the stream idle — an audio-session interruption, the app being
/// backgrounded — makes the current item unplayable rather than merely paused, because a live HLS
/// window rolls off in seconds. Recovery is therefore always the same move: swap in a fresh item,
/// which starts at the live edge.
@MainActor
@Observable
public final class LivePlayerModel {
    public enum State: Equatable, Sendable {
        case loading
        case playing
        case paused
        case failed
    }

    public private(set) var state: State = .loading
    public private(set) var isPlaying: Bool
    public private(set) var isMuted: Bool
    public private(set) var isPictureInPictureActive: Bool
    public private(set) var isPictureInPicturePossible: Bool

    @ObservationIgnored public private(set) lazy var player: AVPlayer = makeAuthedPlayer(url: url, headers: headers)
    @ObservationIgnored private let url: URL
    @ObservationIgnored private let headers: [String: String]
    @ObservationIgnored private let waitForPlayback: @MainActor (Duration) async throws -> Void
    @ObservationIgnored private(set) var playbackDeadline: Task<Void, Never>?
    @ObservationIgnored private var playbackObservation: NSKeyValueObservation?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var didStart = false
    @ObservationIgnored private var didEnterBackground = false
    @ObservationIgnored private var isAudioInterrupted = false
    @ObservationIgnored private var isPictureInPictureStarting = false
    // Set whenever the current item can no longer show live video (its window rolled off while the
    // app was away). Cleared by rebuilding the item, which is deferred until the picture is ours to
    // resume — the user may be paused, or Picture-in-Picture may still own it.
    @ObservationIgnored private var needsFreshLiveItem = false
    // Retained so an active PiP session keeps its source layer alive after the hosting view is torn
    // down (see `PictureInPictureRetainer`).
    @ObservationIgnored private var playerLayer: AVPlayerLayer?
    @ObservationIgnored private var pictureInPictureController: AVPictureInPictureController?
    @ObservationIgnored private var pictureInPictureCoordinator: PictureInPictureCoordinator?
    @ObservationIgnored private var pictureInPicturePossibleObservation: NSKeyValueObservation?
    // Written once during setup, read once in the nonisolated `deinit`; the escape hatch lets deinit
    // unregister the non-Sendable observer token.
    @ObservationIgnored private nonisolated(unsafe) var interruptionObserver: (any NSObjectProtocol)?
    @ObservationIgnored private nonisolated(unsafe) var failureObserver: (any NSObjectProtocol)?

    public var isPictureInPictureSupported: Bool {
        AVPictureInPictureController.isPictureInPictureSupported()
    }

    public convenience init(url: URL, headers: [String: String]) {
        self.init(url: url, headers: headers, waitForPlayback: { try await Task.sleep(for: $0) })
    }

    init(url: URL, headers: [String: String], waitForPlayback: @escaping @MainActor (Duration) async throws -> Void) {
        self.url = url
        self.headers = headers
        self.waitForPlayback = waitForPlayback
        isPlaying = true
        isMuted = false
        isPictureInPictureActive = false
        isPictureInPicturePossible = false
    }

    deinit {
        playbackDeadline?.cancel()
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
    }

    /// Begins playback and interruption handling. Idempotent, and safe to call on the model SwiftUI
    /// keeps — the discarded ones never reach here, so no stream is opened for them.
    public func start() {
        guard !didStart else { return }
        didStart = true
        if player.currentItem == nil {
            player.replaceCurrentItem(with: makeAuthedPlayerItem(url: url, headers: headers))
        }
        needsFreshLiveItem = false
        state = .loading
        isPlaying = true
        observeItemFailure()
        player.play()
        beginPlaybackDeadline()
        observeInterruptions()
    }

    public func stop() {
        guard didStart, !isPictureInPictureActive, !isPictureInPictureStarting,
              pictureInPictureController?.isPictureInPictureActive != true,
              pictureInPictureController?.isPictureInPictureSuspended != true else { return }
        didStart = false
        didEnterBackground = false
        isAudioInterrupted = false
        playbackDeadline?.cancel()
        playbackDeadline = nil
        playbackObservation?.invalidate()
        playbackObservation = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
            self.failureObserver = nil
        }
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
            self.interruptionObserver = nil
        }
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        state = .paused
        needsFreshLiveItem = true
    }

    /// Recovers the stream when the app comes back from the background. The system stops feeding a
    /// backgrounded video layer, and by the time the user returns the live HLS window has rolled
    /// past everything the item buffered — `play()` then has nothing left to show, so the layer sits
    /// on its last frame until the screen is opened afresh. Losing *focus* is not backgrounding (a
    /// banner on iOS, another app's window on macOS): playback survives it, so it must not reload.
    public func handleScenePhase(_ phase: ScenePhase) {
        // Only a stream we actually opened can go stale — recovering one we never started would
        // build the lazy player behind `start()`'s back.
        guard didStart else { return }
        switch phase {
        case .background:
            didEnterBackground = true
            playbackDeadline?.cancel()
            playbackDeadline = nil
        case .inactive:
            break
        case .active:
            guard didEnterBackground else { return }
            didEnterBackground = false
            recoverAfterBackground()
        @unknown default:
            break
        }
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
        if !isPlaying {
            playbackDeadline?.cancel()
            playbackDeadline = nil
            state = .paused
            player.pause()
        } else if needsFreshLiveItem {
            resumeAtLiveEdge()
        } else {
            state = .loading
            player.play()
            beginPlaybackDeadline()
        }
    }

    public func toggleMute() {
        player.isMuted.toggle()
        isMuted = player.isMuted
    }

    public func retry() {
        guard didStart else { return }
        resumeAtLiveEdge()
    }

    public func togglePictureInPicture() {
        guard let controller = pictureInPictureController else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            setPictureInPictureStarting()
            controller.startPictureInPicture()
        }
    }

    func handlePlaybackStatus(_ status: AVPlayer.TimeControlStatus, for item: AVPlayerItem) {
        guard didStart, isPlaying, player.currentItem === item else { return }
        switch status {
        case .playing:
            playbackDeadline?.cancel()
            playbackDeadline = nil
            state = .playing
        case .paused, .waitingToPlayAtSpecifiedRate:
            guard !didEnterBackground, !isAudioInterrupted else { return }
            if state != .loading { state = .loading }
            if playbackDeadline == nil { beginPlaybackDeadline() }
        @unknown default:
            break
        }
    }

    func handleItemStatus(_ status: AVPlayerItem.Status, for item: AVPlayerItem) {
        guard didStart, player.currentItem === item else { return }
        switch status {
        case .failed: failPlayback()
        case .unknown, .readyToPlay: break
        @unknown default: break
        }
    }

    func handleAudioInterruption(_ phase: AudioInterruption) {
        guard didStart else { return }
        switch phase {
        case .began:
            isAudioInterrupted = true
            needsFreshLiveItem = true
            playbackDeadline?.cancel()
            playbackDeadline = nil
        case .ended:
            isAudioInterrupted = false
            if isPlaying { resumeAtLiveEdge() }
        }
    }

    func setPictureInPictureStarting() {
        isPictureInPictureStarting = true
        PictureInPictureRetainer.retain(self)
    }

    func setPictureInPictureActive(_ active: Bool) {
        isPictureInPictureStarting = false
        isPictureInPictureActive = active
        if active {
            PictureInPictureRetainer.retain(self)
        } else {
            // The picture is the inline layer's again. Recover before releasing the retainer, which
            // may be dropping the last reference to this model.
            if isPlaying, needsFreshLiveItem { resumeAtLiveEdge() }
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
            guard let phase = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) else { return }
            MainActor.assumeIsolated {
                switch phase {
                case .began: self?.handleAudioInterruption(.began)
                case .ended: self?.handleAudioInterruption(.ended)
                @unknown default: break
                }
            }
        }
        #endif
    }

    /// Picture-in-Picture kept playing while the app was away and still owns the picture, and a
    /// stream the user paused stays paused — in both cases the stale item is only marked, and the
    /// rebuild happens when playback is handed back or resumed.
    private func recoverAfterBackground() {
        guard isPlaying, !isPictureInPictureActive else {
            needsFreshLiveItem = true
            return
        }
        resumeAtLiveEdge()
    }

    private func resumeAtLiveEdge() {
        guard didStart else { return }
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        needsFreshLiveItem = false
        playbackDeadline?.cancel()
        playbackDeadline = nil
        player.replaceCurrentItem(with: makeAuthedPlayerItem(url: url, headers: headers))
        state = .loading
        observeItemFailure()
        player.play()
        isPlaying = true
        beginPlaybackDeadline()
    }

    private func observeItemFailure() {
        if let failureObserver {
            NotificationCenter.default.removeObserver(failureObserver)
        }
        guard let item = player.currentItem else { return }
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            Task { @MainActor in self?.handleItemStatus(status, for: item) }
        }
        playbackObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self, weak item] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor in
                guard let item else { return }
                self?.handlePlaybackStatus(status, for: item)
            }
        }
        failureObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self, weak item] _ in
            MainActor.assumeIsolated {
                guard let self, let item, self.player.currentItem === item else { return }
                self.failPlayback()
            }
        }
    }

    private func beginPlaybackDeadline() {
        guard !didEnterBackground, !isAudioInterrupted else { return }
        playbackDeadline = Task { [weak self, waitForPlayback] in
            do {
                try await waitForPlayback(.seconds(15))
            } catch {
                guard !Task.isCancelled else { return }
            }
            guard !Task.isCancelled, let self, self.didStart, self.isPlaying, self.state == .loading else { return }
            self.failPlayback()
        }
    }

    private func failPlayback() {
        playbackDeadline?.cancel()
        playbackDeadline = nil
        player.pause()
        isPlaying = false
        state = .failed
        needsFreshLiveItem = true
    }

    enum AudioInterruption {
        case began
        case ended
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

    func pictureInPictureControllerWillStartPictureInPicture(_ controller: AVPictureInPictureController) {
        let model = self.model
        MainActor.assumeIsolated { model?.setPictureInPictureStarting() }
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
