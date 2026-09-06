import Testing

import CommonPlayer

struct AuroraZoomChromeTests {

    @Test func `given rest scale then the border is opaque and the glass is off`() {
        // given - when
        let sut = AuroraZoomChrome(scale: 1)

        // then
        #expect(sut.borderOpacity == 1)
        #expect(sut.glassOpacity == 0)
    }

    @Test func `given a scale past the fill scale then both the border and the glass are off`() {
        // given - when
        let sut = AuroraZoomChrome(scale: 3, fillScale: 3)

        // then
        #expect(sut.borderOpacity == 0)
        #expect(sut.glassOpacity == 0)
    }

    @Test func `given a scale partway into the ramp then the glass fades in while the border stays put`() {
        // given - when
        let sut = AuroraZoomChrome(scale: 1.3, fillScale: 3)

        // then
        #expect(sut.borderOpacity == 1)
        #expect(sut.glassOpacity > 0 && sut.glassOpacity < 1)
    }

    @Test func `given a scale partway into the fade then the border and the glass move together`() {
        // given - when
        let sut = AuroraZoomChrome(scale: 2.3, fillScale: 3)

        // then
        #expect(sut.borderOpacity == sut.glassOpacity)
        #expect(sut.borderOpacity > 0 && sut.borderOpacity < 1)
    }

    @Test func `given the scale at the ramp-to-fade handoff then both read fully opaque`() {
        // given - when
        let sut = AuroraZoomChrome(scale: 1.6, fillScale: 3)

        // then
        #expect(sut.borderOpacity == 1)
        #expect(sut.glassOpacity == 1)
    }
}
