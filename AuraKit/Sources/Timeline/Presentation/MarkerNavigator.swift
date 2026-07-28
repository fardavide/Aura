import Foundation

import TimelineDomain

/// Finds the review marker a jump button should land on, and the one the playhead is inside.
///
/// A jump lands **exactly on** the marker's start, so "next" from there finds the following one
/// without needing a dead zone around the landing instant.
enum MarkerNavigator {

    static func marker(after instant: Date, in markers: [ReviewMarker]) -> ReviewMarker? {
        markers.filter { $0.start > instant }.min { $0.start < $1.start }
    }

    static func marker(before instant: Date, in markers: [ReviewMarker]) -> ReviewMarker? {
        markers.filter { $0.start < instant }.max { $0.start < $1.start }
    }

    /// The marker under the playhead, if any — what the hero badge names. A marker with no `end` is
    /// still in progress, so it stays active from its start onward.
    static func marker(at instant: Date, in markers: [ReviewMarker]) -> ReviewMarker? {
        markers
            .filter { $0.start <= instant && instant < ($0.end ?? .distantFuture) }
            .max { $0.start < $1.start }
    }
}
