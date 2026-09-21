import Foundation

import CamerasEntities

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

    /// Asks the server to cut a new clip from `camera`'s continuous recording, and answers with the
    /// id it assigned. Real-time playback from the recordings, unnamed — Frigate supplies its own
    /// timestamp-derived name, which this app never overrides.
    ///
    /// Returning only the id, not an `Export`, is the server's own shape: the row exists
    /// immediately with `in_progress` true, and the caller follows it with `export(id:)`.
    func createExport(camera: CameraName, from: Date, to: Date) async throws(ExportsError) -> ExportId
}
