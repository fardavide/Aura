import Foundation
import Testing

@testable import CommonNetwork

struct UrlSessionHttpClientTests {

    @Test func `when building the client then the session bounds total transfer time`() {
        // given - when
        let sut = UrlSessionHttpClient()

        // then
        #expect(sut.session.configuration.timeoutIntervalForResource == 600)
    }
}
