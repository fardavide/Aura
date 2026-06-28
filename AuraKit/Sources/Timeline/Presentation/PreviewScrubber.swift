import Foundation

/// Drives one tile's actual preview update — seeking the clip player or loading the nearest
/// frame. The controller calls `scrub(to:completion:)` and coalesces calls behind `completion`,
/// so this stays a thin, swappable seam (real AVPlayer-backed impl vs. a test fake).
@MainActor
protocol PreviewScrubber: AnyObject {
    func scrub(to time: Date, completion: @escaping @MainActor () -> Void)
}
