import Testing

@testable import CommonNetwork

struct AuthorizationHeaderTests {

    @Test func `when building a basic header then credentials are base64 encoded`() {
        // given - when
        let header = AuthorizationHeader.basic(username: "admin", password: "secret")

        // then  (base64 of "admin:secret")
        #expect(header == "Basic YWRtaW46c2VjcmV0")
    }

    @Test func `given missing credentials when building a basic header then it is nil`() {
        // given - when - then
        #expect(AuthorizationHeader.basic(username: nil, password: nil) == nil)
        #expect(AuthorizationHeader.basic(username: "admin", password: nil) == nil)
    }
}
