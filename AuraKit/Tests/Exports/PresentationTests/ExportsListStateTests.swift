import Testing

import ExportsDomain
@testable import ExportsPresentation

struct ExportsListStateTests {

    @Test func `given a loaded list then it has content`() {
        #expect(ExportsListState.loaded([]).hasContent)
    }

    @Test(arguments: [ExportsListState.loading, .empty, .failed(.unreachable)])
    func `given a state with no rows then it has no content`(state: ExportsListState) {
        #expect(state.hasContent == false)
    }
}
