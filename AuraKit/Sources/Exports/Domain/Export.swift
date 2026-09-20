import Foundation

import CamerasEntities

/// One clip Frigate has cut out of a camera's continuous recording and kept on the server.
///
/// The record is the server's, not Aura's: the name is Frigate's own timestamp-derived one, and
/// `isProcessing` is the server's answer rather than something inferred from elapsed time. The two
/// media paths are Frigate's `/media/frigate/…` server paths, already validated by the Data layer
/// that built this value and resolved to URLs there — the same shape `PreviewClip` carries.
///
/// There is deliberately no duration: `/api/exports` does not report one, and the timestamp-derived
/// name encodes only where the clip starts. Presentation omits the overlay rather than guessing.
public struct Export: Equatable, Hashable, Sendable, Identifiable {
    public let id: ExportId
    public let camera: CameraName
    /// Frigate's own file name for the clip, e.g. `driveway_20260918_143012`. Aura never renames it.
    public let name: String
    public let createdAt: Date
    /// The server is still cutting this clip. While true nothing can play or download it.
    public let isProcessing: Bool
    /// Server path to the finished mp4.
    public let videoPath: String
    /// Server path to the still, when the server kept one. A clip without it is ordinary.
    public let thumbnailPath: String?

    public init(
        id: ExportId,
        camera: CameraName,
        name: String,
        createdAt: Date,
        isProcessing: Bool,
        videoPath: String,
        thumbnailPath: String?
    ) {
        self.id = id
        self.camera = camera
        self.name = name
        self.createdAt = createdAt
        self.isProcessing = isProcessing
        self.videoPath = videoPath
        self.thumbnailPath = thumbnailPath
    }

    /// Whether the clip can be played or copied. The one gate both actions read, so a processing
    /// card can never present an operable control (dead-control audit).
    public var isReady: Bool {
        !isProcessing
    }
}
