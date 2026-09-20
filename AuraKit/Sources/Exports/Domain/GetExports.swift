/// Returns the server's whole export library, newest first.
///
/// The sort is applied here rather than trusted from the server: the list's only ordering promise
/// is "newest first, always", and it must hold whatever order the endpoint happens to answer in.
public struct GetExports: Sendable {
    private let repository: any ExportsRepository

    public init(repository: any ExportsRepository) {
        self.repository = repository
    }

    public func execute() async throws(ExportsError) -> [Export] {
        try await repository.exports().sorted { $0.createdAt > $1.createdAt }
    }
}
