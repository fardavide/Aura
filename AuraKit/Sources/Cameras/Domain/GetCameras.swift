/// Returns the cameras worth showing — the enabled ones.
public struct GetCameras: Sendable {
    private let repository: any CamerasRepository

    public init(repository: any CamerasRepository) {
        self.repository = repository
    }

    public func execute() async throws(CamerasError) -> [Camera] {
        try await repository.cameras().filter(\.isEnabled)
    }
}
