/// Whether this server takes detection feedback — the paid add-on that trains the model on your
/// own footage. Off on most deployments, so the screen asks before offering to report anything.
public struct IsDetectionFeedbackEnabled: Sendable {
    private let repository: any EventsRepository

    public init(repository: any EventsRepository) {
        self.repository = repository
    }

    public func execute() async throws(EventsError) -> Bool {
        try await repository.isDetectionFeedbackEnabled()
    }
}
