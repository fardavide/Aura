import Foundation

/// The exports created on one calendar day, newest first. The list's only grouping — a library of
/// clips you cut yourself is scanned by when, and day headings already answer it.
public struct ExportDayGroup: Equatable, Sendable, Identifiable {
    public let dayStart: Date
    public let exports: [Export]

    public init(dayStart: Date, exports: [Export]) {
        self.dayStart = dayStart
        self.exports = exports
    }

    public var id: Date { dayStart }
}
