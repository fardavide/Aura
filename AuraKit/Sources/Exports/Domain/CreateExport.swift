import Foundation

import CamerasEntities

/// Asks the server to cut a clip, and answers with the id to follow it by.
///
/// The bounds are floored to whole seconds here rather than at the transport: Frigate 0.17.2
/// converts them to integers before exporting, so submitting fractions would mean the readout the
/// user committed to and the file they get disagree about where the clip starts.
public struct CreateExport: Sendable {
    private let repository: any ExportsRepository

    public init(repository: any ExportsRepository) {
        self.repository = repository
    }

    public func execute(camera: CameraName, from: Date, to: Date) async throws(ExportsError) -> ExportId {
        try await repository.createExport(
            camera: camera,
            from: Date(timeIntervalSince1970: from.timeIntervalSince1970.rounded(.down)),
            to: Date(timeIntervalSince1970: to.timeIntervalSince1970.rounded(.down))
        )
    }
}
