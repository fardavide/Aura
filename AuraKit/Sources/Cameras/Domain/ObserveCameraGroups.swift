/// The camera groups worth offering as filter chips — the non-empty ones, sorted by the server's
/// `order` then name so the chips are stable. Re-emits whenever the server config is re-read.
public struct ObserveCameraGroups: Sendable {
    private let repository: any CameraGroupsRepository

    public init(repository: any CameraGroupsRepository) {
        self.repository = repository
    }

    public func execute() -> AsyncStream<[CameraGroup]> {
        let groups = repository.observeGroups()
        return AsyncStream { continuation in
            let task = Task {
                for await list in groups {
                    continuation.yield(
                        list
                            .filter { !$0.cameraNames.isEmpty }
                            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
