import SwiftUI
import Testing

import CommonDesign
import TimelineDomain
@testable import TimelinePresentation

/// `TimelineTrackStyle` is the one vocabulary the tab's histogram, the detail's scrub track and the
/// day-overview bar all paint through — these tests pin that it stays a pure delegation to
/// `AuroraTrack` rather than drifting into its own copy of the thresholds or tones.
struct TimelineTrackStyleTests {

    @Test func `given a quiet motion bucket when the track style picks a colour then it is the design's low intensity paint`() {
        #expect(TimelineTrackStyle.motionColor(intensity: 12) == AuroraTrack.motionColor(intensity: 12))
    }

    @Test func `given a busy motion bucket when the track style picks a colour then it is the design's high intensity paint`() {
        #expect(TimelineTrackStyle.motionColor(intensity: 90) == AuroraTrack.motionColor(intensity: 90))
    }

    @Test func `given an alert marker when the track style picks a colour then it is the design's alert tone`() {
        #expect(TimelineTrackStyle.markerColor(for: .alert) == AuroraTrack.markerColor(for: .alert))
    }

    @Test func `given a detection marker when the track style picks a colour then it is the design's detection tone`() {
        #expect(TimelineTrackStyle.markerColor(for: .detection) == AuroraTrack.markerColor(for: .detection))
    }
}
