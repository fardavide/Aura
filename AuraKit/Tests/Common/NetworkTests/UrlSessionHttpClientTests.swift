import Foundation
import Testing

@testable import CommonNetwork

struct UrlSessionHttpClientTests {

    @Test func `when building the client then the session bounds total transfer time`() {
        // given - when
        let sut = UrlSessionHttpClient()

        // then
        #expect(!sut.session.configuration.waitsForConnectivity)
        #expect(sut.session.configuration.timeoutIntervalForResource == 600)
    }

    @Test func `when building the config client then it waits for connectivity for at most thirty seconds`() {
        // given - when
        let sut = UrlSessionHttpClient(waitsForConnectivity: true)

        // then
        #expect(sut.session.configuration.waitsForConnectivity)
        #expect(sut.session.configuration.timeoutIntervalForResource == 30)
    }
}
