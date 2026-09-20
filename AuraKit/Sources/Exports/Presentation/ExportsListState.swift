import Foundation

import ExportsDomain

/// What the Exports list is showing.
///
/// Refreshing and a failed refresh are deliberately **not** cases here. Once the list has rendered,
/// the state can never return to `.loading` or become `.failed` — a refresh is a separate flag and
/// a failed refresh a separate error, so neither can blank content the user is looking at. Keeping
/// them out of this enum is what makes that unrepresentable rather than merely intended.
public enum ExportsListState: Equatable, Sendable {
    /// First paint, nothing cached. Carries no controls at all: a tappable ghost row is the worst
    /// kind of dead control.
    case loading
    /// The server answered with an empty library. Teaches where clips are actually cut.
    case empty
    /// The first load failed, so there is nothing to keep on screen.
    case failed(ExportsError)
    case loaded([ExportDayGroup])

    /// Whether rows are on screen — the condition under which a later failure must degrade to a
    /// banner instead of replacing the list.
    public var hasContent: Bool {
        if case .loaded = self { return true }
        return false
    }
}
