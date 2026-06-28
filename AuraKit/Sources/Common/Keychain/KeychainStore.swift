/// A minimal secret string store. Abstracted so the Data layer is testable with a fake —
/// the real Keychain needs entitlements and isn't reachable from unit tests.
public protocol KeychainStore: Sendable {
    func string(for key: String) -> String?
    /// Stores `value`, or removes the entry when `value` is nil.
    func set(_ value: String?, for key: String)
}
