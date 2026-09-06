import SwiftUI
import Testing

@testable import CommonDesign

@Suite
struct AuroraTrackTests {
    @Test
    func `given intensity 34 35 64 65 when choosing motion colour then blue violet violet pink`() {
        // given - when
        let atThirtyFour = AuroraTrack.motionColor(intensity: 34)
        let atThirtyFive = AuroraTrack.motionColor(intensity: 35)
        let atSixtyFour = AuroraTrack.motionColor(intensity: 64)
        let atSixtyFive = AuroraTrack.motionColor(intensity: 65)

        // then
        #expect(atThirtyFour == .auroraGradientBlue)
        #expect(atThirtyFive == .auroraGradientViolet)
        #expect(atSixtyFour == .auroraGradientViolet)
        #expect(atSixtyFive == .auroraGradientPink)
    }

    @Test
    func `given alert and detection tones when choosing marker colour then alert marker and detection`() {
        // given - when
        let alert = AuroraTrack.markerColor(for: .alert)
        let detection = AuroraTrack.markerColor(for: .detection)

        // then
        #expect(alert == .auroraAlertMarker)
        #expect(detection == .auroraDetection)
    }
}
