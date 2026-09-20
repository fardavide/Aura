/// Re-reads one export — how a processing clip is followed to ready without re-reading the library.
public struct GetExport: Sendable {
    private let repository: any ExportsRepository

    public init(repository: any ExportsRepository) {
        self.repository = repository
    }

    public func execute(id: ExportId) async throws(ExportsError) -> Export {
        try await repository.export(id: id)
    }
}
