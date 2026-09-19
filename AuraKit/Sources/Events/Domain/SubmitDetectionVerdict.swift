/// Tells the server whether a detection's label was right, putting its snapshot in the training
/// dataset either way.
public struct SubmitDetectionVerdict: Sendable {
    private let repository: any EventsRepository

    public init(repository: any EventsRepository) {
        self.repository = repository
    }

    public func execute(_ verdict: DetectionVerdict, for event: EventId) async throws(EventsError) {
        try await repository.submit(verdict, for: event)
    }
}
