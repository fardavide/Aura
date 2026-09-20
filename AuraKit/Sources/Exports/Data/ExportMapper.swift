import Foundation

import CamerasEntities
import CommonFrigate
import ExportsDomain

extension [ExportDto] {
    /// Maps the wire rows, dropping any whose video path the media resolver refuses.
    ///
    /// Dropping is deliberate. The alternative — keeping the row with Play and Download inert — is
    /// exactly the dead control the app does not ship, and there is no honest state to draw for
    /// "the server described a file we will not fetch". A refused row is a server bug, not a user
    /// situation, so it leaves the list rather than explaining itself.
    func toExports(base: URL) -> [Export] {
        compactMap { $0.toExport(base: base) }
    }
}

extension ExportDto {
    func toExport(base: URL) -> Export? {
        guard FrigateExportMediaUrl.media(base: base, serverPath: videoPath) != nil else { return nil }
        // A thumbnail that fails the same check is not fatal: the card has a first-class
        // no-thumbnail variant, so the clip is still perfectly usable without it.
        let thumbnail = thumbPath.flatMap { path in
            FrigateExportMediaUrl.media(base: base, serverPath: path) == nil ? nil : path
        }
        return Export(
            id: ExportId(id),
            camera: CameraName(camera),
            name: name,
            createdAt: Date(timeIntervalSince1970: date),
            isProcessing: inProgress ?? false,
            videoPath: videoPath,
            thumbnailPath: thumbnail
        )
    }
}
