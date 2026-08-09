/// Switches the Home Screen icon. Nothing is persisted alongside it — the system keeps the
/// choice, and a rejected change leaves the previous icon in place.
@MainActor
public struct ChangeAppIcon {
    private let switcher: any AppIconSwitcher

    public init(switcher: any AppIconSwitcher) {
        self.switcher = switcher
    }

    public func execute(_ icon: AppIconPreference) async throws(SettingsError) {
        try await switcher.apply(icon)
    }
}
