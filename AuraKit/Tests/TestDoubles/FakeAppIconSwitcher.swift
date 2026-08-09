import SettingsDomain

/// In-memory icon switcher: `current` reflects the last accepted change, so round-trip tests
/// and pre-seeded screens use the same fake. A configured failure leaves the icon untouched,
/// matching a system that rejects the change.
@MainActor
public final class FakeAppIconSwitcher: AppIconSwitcher {
    public var isSupported = true
    public var currentIcon: AppIconPreference
    public var applyResult: Result<Void, SettingsError>
    public private(set) var appliedIcons: [AppIconPreference] = []

    public init(
        current: AppIconPreference = .halo,
        applyResult: Result<Void, SettingsError> = .success(())
    ) {
        currentIcon = current
        self.applyResult = applyResult
    }

    public func current() -> AppIconPreference { currentIcon }

    public func apply(_ icon: AppIconPreference) async throws(SettingsError) {
        appliedIcons.append(icon)
        try applyResult.get()
        currentIcon = icon
    }
}
