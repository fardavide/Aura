/// The camera groups worth offering as filter chips — the non-empty ones, sorted by the server's
/// `order` then name so the chips are stable.
public struct GetCameraGroups: Sendable {
    private let repository: any CameraGroupsRepository

    public init(repository: any CameraGroupsRepository) {
        self.repository = repository
    }

    public func execute() async throws(CamerasError) -> [CameraGroup] {
        try await repository.groups()
            .filter { !$0.cameraNames.isEmpty }
            .sorted { ($0.order, $0.name) < ($1.order, $1.name) }
    }
}
