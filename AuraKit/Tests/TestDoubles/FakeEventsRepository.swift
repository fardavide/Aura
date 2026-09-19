import Foundation

import EventsDomain

/// Replays a canned result; `result` is mutable so a test can change the outcome between calls.
/// `olderResult`, when set, answers only the cursored reads (the older pages), leaving `result`
/// as the newest page — so one fake covers a first load followed by a paged load.
public final class FakeEventsRepository: EventsRepository, @unchecked Sendable {
    public var result: Result<[Event], EventsError>
    public var olderResult: Result<[Event], EventsError>?
    public var detectionFeedbackEnabled: Result<Bool, EventsError>
    public var submitResult: Result<Void, EventsError>
    public private(set) var requestedCursors: [Date?] = []
    public private(set) var submittedVerdicts: [(verdict: DetectionVerdict, event: EventId)] = []

    public init(
        _ result: Result<[Event], EventsError>,
        olderResult: Result<[Event], EventsError>? = nil,
        detectionFeedbackEnabled: Result<Bool, EventsError> = .success(false),
        submitResult: Result<Void, EventsError> = .success(())
    ) {
        self.result = result
        self.olderResult = olderResult
        self.detectionFeedbackEnabled = detectionFeedbackEnabled
        self.submitResult = submitResult
    }

    public func events(limit: Int, before: Date?) async throws(EventsError) -> [Event] {
        requestedCursors.append(before)
        if before != nil, let olderResult {
            return try olderResult.get()
        }
        return try result.get()
    }

    public func isDetectionFeedbackEnabled() async throws(EventsError) -> Bool {
        try detectionFeedbackEnabled.get()
    }

    public func submit(_ verdict: DetectionVerdict, for event: EventId) async throws(EventsError) {
        submittedVerdicts.append((verdict: verdict, event: event))
        try submitResult.get()
    }
}
