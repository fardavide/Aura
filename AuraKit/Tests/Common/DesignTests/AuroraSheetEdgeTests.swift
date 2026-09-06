import Testing

@testable import CommonDesign

@Suite
struct AuroraSheetEdgeTests {
    @Test
    func `given bottom edge when reading shape then only the top corners are rounded`() {
        // given - when
        let shape = AuroraSheetEdge.bottom.shape

        // then
        #expect(shape.cornerRadii.topLeading == 30)
        #expect(shape.cornerRadii.topTrailing == 30)
        #expect(shape.cornerRadii.bottomLeading == 0)
        #expect(shape.cornerRadii.bottomTrailing == 0)
        #expect(AuroraSheetEdge.bottom.flushEdge == .bottom)
    }

    @Test
    func `given trailing edge when reading shape then only the leading corners are rounded`() {
        // given - when
        let shape = AuroraSheetEdge.trailing.shape

        // then
        #expect(shape.cornerRadii.topLeading == 30)
        #expect(shape.cornerRadii.bottomLeading == 30)
        #expect(shape.cornerRadii.topTrailing == 0)
        #expect(shape.cornerRadii.bottomTrailing == 0)
        #expect(AuroraSheetEdge.trailing.flushEdge == .trailing)
    }
}
