import CamerasEntities

/// A user-defined camera group from the Frigate config (the grid's filter chips). `order` is the
/// server-assigned position; the grid sorts by it. A group naming no live camera (e.g. only the
/// Birdseye view) carries an empty `cameraNames` and is dropped before it reaches the chips.
public struct CameraGroup: Equatable, Hashable, Sendable, Identifiable {
    public let name: String
    public let cameraNames: [CameraName]
    public let order: Int

    public init(name: String, cameraNames: [CameraName], order: Int) {
        self.name = name
        self.cameraNames = cameraNames
        self.order = order
    }

    public var id: String { name }

    public func contains(_ camera: CameraName) -> Bool {
        cameraNames.contains(camera)
    }
}
