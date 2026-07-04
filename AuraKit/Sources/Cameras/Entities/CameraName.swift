/// The Frigate-assigned identity of a camera. A typed wrapper so a `CameraName`
/// can never be confused with another string-backed identifier.
public struct CameraName: Hashable, Comparable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }

    public static func < (lhs: CameraName, rhs: CameraName) -> Bool {
        lhs.value < rhs.value
    }
}
