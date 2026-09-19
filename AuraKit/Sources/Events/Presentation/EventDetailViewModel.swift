import Foundation
import Observation

import EventsDomain

@Observable
@MainActor
public final class EventDetailViewModel {
    public enum State: Equatable {
        case unavailable
        case loading
        case ready(Data)
        case failed
    }

    /// Where the detection-feedback panel stands. It starts `.unavailable` and only leaves that
    /// state once the server has confirmed it takes feedback *and* this event is one it can
    /// accept — a control that reports nothing is worse than no control at all.
    public enum Feedback: Equatable {
        case unavailable
        case ready
        case sending
        /// A verdict is on record; `verdict` says which.
        case submitted
        case failed(DetectionVerdict, EventsError)
    }

    public let label: String
    public let severity: EventSeverity
    public let startTime: Date
    public let duration: Duration?
    public private(set) var state: State
    public private(set) var feedback: Feedback = .unavailable
    /// The verdict on record — seeded from the list's copy, corrected by the server on open, and
    /// updated when one is given here. Drives the struck-through label, which stands even when the
    /// panel itself is hidden, so the screen never disagrees with the row it was opened from.
    public private(set) var verdict: DetectionVerdict?

    private let event: Event
    private let clipLoader: any EventClipLoading
    private let getEvent: GetEvent
    private let isDetectionFeedbackEnabled: IsDetectionFeedbackEnabled
    private let submitDetectionVerdict: SubmitDetectionVerdict

    public init(
        event: Event,
        clipLoader: any EventClipLoading,
        getEvent: GetEvent,
        isDetectionFeedbackEnabled: IsDetectionFeedbackEnabled,
        submitDetectionVerdict: SubmitDetectionVerdict
    ) {
        self.event = event
        self.clipLoader = clipLoader
        self.getEvent = getEvent
        self.isDetectionFeedbackEnabled = isDetectionFeedbackEnabled
        self.submitDetectionVerdict = submitDetectionVerdict
        label = event.label
        severity = event.severity
        startTime = event.startTime
        duration = event.endTime.map { Duration.seconds($0.timeIntervalSince(event.startTime)) }
        verdict = event.verdict
        state = event.hasClip ? .loading : .unavailable
    }

    public func load() async {
        guard event.hasClip else { return }
        state = .loading
        if let data = await clipLoader.downloadClip(for: event) {
            state = .ready(data)
        } else {
            state = .failed
        }
    }

    /// Runs alongside the clip download rather than after it, so the panel doesn't wait on a whole
    /// MP4. Re-entrant: a second appearance never walks back a verdict already given.
    public func loadFeedback() async {
        switch feedback {
        case .unavailable: break
        case .ready, .sending, .submitted, .failed: return
        }
        guard canSubmit || verdict != nil else { return }
        // Best effort: a failed capability read leaves the panel hidden, never shown-and-broken.
        guard (try? await isDetectionFeedbackEnabled.execute()) == true else { return }
        // The list's copy ages the moment a verdict is given — here, on another device, or in
        // Frigate's own web UI — and only the server knows the current answer. A failed re-read
        // falls back to what the list said rather than blocking the panel.
        verdict = (try? await getEvent.execute(event.id))?.verdict ?? verdict
        feedback = verdict == nil ? .ready : .submitted
    }

    public func submit(_ verdict: DetectionVerdict) async {
        switch feedback {
        case .ready, .failed: break
        case .unavailable, .sending, .submitted: return
        }
        feedback = .sending
        do {
            try await submitDetectionVerdict.execute(verdict, for: event.id)
            self.verdict = verdict
            feedback = .submitted
        } catch {
            feedback = .failed(verdict, error)
        }
    }

    /// The server refuses an in-progress event (no clean snapshot is written until it ends), one
    /// with no snapshot at all, and anything that isn't a tracked object — there is no bounding box
    /// to attach a verdict to.
    private var canSubmit: Bool {
        event.hasSnapshot && event.endTime != nil && event.isObjectDetection
    }
}
