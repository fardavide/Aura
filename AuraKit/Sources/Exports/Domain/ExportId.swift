/// A Frigate export's identity. Typed wrapper so it can't be confused with another string id.
public struct ExportId: Hashable, Sendable {
    public let value: String

    public init(_ value: String) {
        self.value = value
    }
}
