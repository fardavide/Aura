public struct AppIconSettings: Equatable, Sendable {
    public let selection: AppIconPreference
    public let usesSeasonalIcons: Bool

    public init(selection: AppIconPreference, usesSeasonalIcons: Bool) {
        self.selection = selection
        self.usesSeasonalIcons = usesSeasonalIcons
    }
}
