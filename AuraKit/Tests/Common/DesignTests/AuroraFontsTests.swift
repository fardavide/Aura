import Testing

@testable import CommonDesign

@Suite
struct AuroraFontsTests {
    @Test
    func `given bundled fonts when registering then every Urbanist face resolves by PostScript name`() {
        // given - when
        let registered = AuroraFonts.isRegistered

        // then
        #expect(registered)
    }

    @Test
    func `given fonts already registered when registering again then isRegistered stays true`() {
        // given
        _ = AuroraFonts.isRegistered

        // when
        let registeredAgain = AuroraFonts.isRegistered

        // then
        #expect(registeredAgain)
    }
}
