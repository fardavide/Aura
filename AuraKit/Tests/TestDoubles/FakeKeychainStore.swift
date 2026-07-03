import CommonKeychain

/// Dictionary-backed keychain — no Security framework, no persistence.
public final class FakeKeychainStore: KeychainStore, @unchecked Sendable {
    private var storage: [String: String] = [:]

    public init() {}

    public func string(for key: String) -> String? { storage[key] }
    public func set(_ value: String?, for key: String) { storage[key] = value }
}
