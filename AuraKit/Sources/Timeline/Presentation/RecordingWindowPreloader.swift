import AVFoundation

import CamerasEntities
import TimelineDomain

/// Keeps only the following fast-forward window in flight while current footage plays.
@MainActor
final class RecordingWindowPreloader {
    private let camera: CameraName
    private let recordings: GetCameraRecordings
    private var state: State = .idle
    private var generation = 0

    init(camera: CameraName, recordings: GetCameraRecordings) {
        self.camera = camera
        self.recordings = recordings
    }

    isolated deinit { cancel() }

    func prepare(window: TimeRange) {
        if case .loading(let current, _, _) = state, current == window { return }
        cancel()
        let task = Task { [camera, recordings] () -> Result<PreparedRecordingWindow, TimelineError> in
            do throws(TimelineError) {
                let recording = try await recordings.execute(for: camera, in: window, mode: .fastForward)
                guard !Task.isCancelled else { return .failure(.invalidData) }
                guard recording.timeline.playableDuration > 0 else { return .success(.empty(recording)) }
                let player = try await makeRecordingPlayer(source: recording.source)
                let readiness = AsyncStream<AVPlayer.Status>.makeStream(bufferingPolicy: .bufferingNewest(1))
                let observation = player.observe(\.status, options: [.initial, .new]) { player, _ in
                    readiness.continuation.yield(player.status)
                }
                defer {
                    observation.invalidate()
                    readiness.continuation.finish()
                }
                for await status in readiness.stream {
                    switch status {
                    case .unknown: continue
                    case .readyToPlay:
                        guard !Task.isCancelled else { return .failure(.invalidData) }
                        return .success(.playable(recording, player))
                    case .failed: return .failure(.invalidData)
                    @unknown default: return .failure(.invalidData)
                    }
                }
                return .failure(.invalidData)
            } catch {
                return .failure(error)
            }
        }
        state = .loading(window, task, .speculative)
    }

    func cancel() {
        generation += 1
        if case .loading(_, let task, _) = state { task.cancel() }
        state = .idle
    }

    func load(window: TimeRange, mode: RecordingMode) async throws(TimelineError) -> PreparedRecordingWindow {
        while mode == .fastForward, case .loading(let current, let task, let purpose) = state, current == window {
            let loadingGeneration = generation
            let result = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            guard generation == loadingGeneration, !Task.isCancelled else { throw .invalidData }
            switch result {
            case .success(let prepared): return prepared
            case .failure(let error):
                switch purpose {
                case .recovery:
                    state = .idle
                    throw error
                case .speculative:
                    // Rollover and a newer seek can both consume this result. They must share
                    // one recovery without either consumer invalidating the other's request.
                    if case .loading(_, _, .speculative) = state {
                        let recovery = Task { [camera, recordings] () -> Result<PreparedRecordingWindow, TimelineError> in
                            do throws(TimelineError) {
                                return .success(.unprepared(try await recordings.execute(for: camera, in: window, mode: mode)))
                            } catch {
                                return .failure(error)
                            }
                        }
                        state = .loading(window, recovery, .recovery)
                    }
                }
            }
        }
        cancel()
        return .unprepared(try await recordings.execute(for: camera, in: window, mode: mode))
    }

    private enum State {
        case idle
        case loading(TimeRange, Task<Result<PreparedRecordingWindow, TimelineError>, Never>, LoadingPurpose)
    }

    private enum LoadingPurpose {
        case speculative
        case recovery
    }
}

enum PreparedRecordingWindow {
    case unprepared(RecordingPlayback)
    case empty(RecordingPlayback)
    case playable(RecordingPlayback, AVPlayer)

    var recording: RecordingPlayback {
        switch self {
        case .unprepared(let recording), .empty(let recording), .playable(let recording, _): recording
        }
    }
}
