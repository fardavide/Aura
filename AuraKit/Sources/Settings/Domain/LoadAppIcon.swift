@MainActor
public struct LoadAppIcon {
    private let switcher: any AppIconSwitcher
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository, switcher: any AppIconSwitcher) {
        self.repository = repository
        self.switcher = switcher
    }

    public func execute() -> (settings: AppIconSettings, displayed: AppIconPreference) {
        let displayed = switcher.current()
        let settings = repository.loadAppIconSettings()
            ?? AppIconSettings(selection: displayed, usesSeasonalIcons: true)
        return (settings, displayed)
    }
}
