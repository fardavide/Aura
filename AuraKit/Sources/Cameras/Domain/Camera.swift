/// A camera exposed by the server.
public struct Camera: Equatable, Hashable, Sendable, Identifiable {
    public let name: CameraName
    public let friendlyName: String?
    public let isEnabled: Bool
    /// The live-stream source names this camera can be viewed through.
    public let streamNames: [String]

    public init(name: CameraName, friendlyName: String?, isEnabled: Bool, streamNames: [String]) {
        self.name = name
        self.friendlyName = friendlyName
        self.isEnabled = isEnabled
        self.streamNames = streamNames
    }

    public var id: CameraName { name }
}
