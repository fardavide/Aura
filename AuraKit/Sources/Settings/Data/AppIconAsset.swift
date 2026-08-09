import SettingsDomain

/// Maps icon choices to the asset catalog names the system knows them by.
///
/// The icon the app ships with has no name of its own: the system addresses the primary icon
/// with `nil`, and only the alternates are named. The switch is exhaustive on purpose — a new
/// icon has to be given a catalog entry here before it compiles.
enum AppIconAsset {

    static func name(for icon: AppIconPreference) -> String? {
        switch icon {
        case .halo: nil
        case .heavy: "AppIcon-Heavy"
        case .thin: "AppIcon-Thin"
        case .sweep: "AppIcon-Sweep"
        case .aurora: "AppIcon-Aurora"
        case .signal: "AppIcon-Signal"
        case .daylight: "AppIcon-Daylight"
        }
    }

    /// Falls back to the shipped icon for a name we no longer recognise — an icon dropped from
    /// a later build leaves the system still reporting its old name.
    static func icon(named name: String) -> AppIconPreference {
        AppIconPreference.allCases.first { self.name(for: $0) == name } ?? .halo
    }
}
