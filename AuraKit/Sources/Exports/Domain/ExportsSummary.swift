/// The header subtitle's two numbers — "14 clips · 4 cameras".
///
/// This is what ships instead of a filter row: it answers the question a filter would be asked
/// first, costs one line, and cannot be tapped and disappoint anyone.
public struct ExportsSummary: Equatable, Sendable {
    public let clipCount: Int
    public let cameraCount: Int

    public init(clipCount: Int, cameraCount: Int) {
        self.clipCount = clipCount
        self.cameraCount = cameraCount
    }
}
