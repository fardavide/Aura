import Foundation

@testable import TimelinePresentation

/// Stays in this test target (not `TestDoubles`): `PreviewScrubber` is internal to
/// `TimelinePresentation`, so a shared module cannot conform to it.
@MainActor
final class FakeScrubber: PreviewScrubber {
    private(set) var targets: [Date] = []
    private var completion: (@MainActor () -> Void)?

    func scrub(to time: Date, completion: @escaping @MainActor () -> Void) {
        targets.append(time)
        self.completion = completion
    }

    func complete() {
        let pending = completion
        completion = nil
        pending?()
    }
}
