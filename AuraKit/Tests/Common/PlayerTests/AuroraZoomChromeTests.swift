import Testing

import CommonPlayer

struct AuroraZoomChromeTests {

    @Test func `given rest scale then the border is opaque and the picture is sharp`() {
        // given - when
        let sut = AuroraZoomChrome(scale: 1, maxBlurRadius: 24)

        // then
        #expect(sut.borderOpacity == 1)
        #expect(sut.imageBlurRadius == 0)
    }

    @Test func `given a scale past the fill scale then the border is gone and the picture is sharp`() {
        // given - when
        let sut = AuroraZoomChrome(scale: 3, fillScale: 3, maxBlurRadius: 24)

        // then
        #expect(sut.borderOpacity == 0)
        #expect(sut.imageBlurRadius == 0)
    }

    @Test func `given a scale partway into the ramp then the blur rises while the border stays put`() {
        // given - when
        let sut = AuroraZoomChrome(scale: 1.3, fillScale: 3, maxBlurRadius: 24)

        // then
        #expect(sut.borderOpacity == 1)
        #expect(sut.imageBlurRadius > 0 && sut.imageBlurRadius < 24)
    }

    @Test func `given a scale partway into the fade then the border and the blur move together`() {
        // given - when
        let sut = AuroraZoomChrome(scale: 2.3, fillScale: 3, maxBlurRadius: 24)

        // then
        #expect(sut.borderOpacity == Double(sut.imageBlurRadius / 24))
        #expect(sut.borderOpacity > 0 && sut.borderOpacity < 1)
    }

    @Test func `given the scale at the ramp-to-fade handoff then the border is opaque and the blur peaks`() {
        // given - when
        let sut = AuroraZoomChrome(scale: 1.6, fillScale: 3, maxBlurRadius: 24)

        // then
        #expect(sut.borderOpacity == 1)
        #expect(sut.imageBlurRadius == 24)
    }
}
