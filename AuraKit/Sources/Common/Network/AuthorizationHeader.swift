import Foundation

/// Builds `Authorization` header values. Kept generic so the same seam can carry a
/// `Bearer` token later without touching call sites.
public enum AuthorizationHeader {

    /// HTTP Basic credentials encoded for the `Authorization` header, or `nil` when
    /// either credential is absent (no auth).
    public static func basic(username: String?, password: String?) -> String? {
        guard let username, let password else { return nil }
        let encoded = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(encoded)"
    }
}
