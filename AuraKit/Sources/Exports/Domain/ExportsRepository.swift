/// The boundary the Exports feature depends on to read the server's clip library. Implemented in
/// the Data layer.
public protocol ExportsRepository: Sendable {

    /// Every export the server holds, newest first. Frigate has no paging here — the endpoint
    /// answers with the whole library, which for a personal deployment is a short list.
    func exports() async throws(ExportsError) -> [Export]

    /// Re-reads one export. Used to follow a clip that was still processing without re-reading the
    /// whole library, and `in_progress` is the server's answer — readiness is never inferred from
    /// elapsed time.
    func export(id: ExportId) async throws(ExportsError) -> Export
}
