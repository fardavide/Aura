import Foundation

/// Applies the active seasonal icon or the user's usual selection to the Home Screen.
@MainActor
public struct ChangeAppIcon {
    public enum Request: Sendable {
        case select(AppIconPreference)
        case setSeasonalIcons(Bool)
        case refresh
    }

    private let switcher: any AppIconSwitcher
    private let repository: any SettingsRepository

    public init(repository: any SettingsRepository, switcher: any AppIconSwitcher) {
        self.repository = repository
        self.switcher = switcher
    }

    public func execute(_ request: Request, at date: Date, in timeZone: TimeZone) async throws(SettingsError) {
        let displayedIcon = switcher.current()
        let saved = repository.loadAppIconSettings()
        let previous = saved ?? AppIconSettings(selection: displayedIcon, usesSeasonalIcons: true)
        let next = switch request {
        case let .select(icon):
            AppIconSettings(selection: icon, usesSeasonalIcons: previous.usesSeasonalIcons)
        case let .setSeasonalIcons(isEnabled):
            AppIconSettings(selection: previous.selection, usesSeasonalIcons: isEnabled)
        case .refresh:
            previous
        }

        // Save the usual icon before changing it on an install that only has a system selection.
        if next != saved { repository.saveAppIconSettings(next) }

        let seasonalIcon = next.usesSeasonalIcons ? SeasonalAppIcon.active(at: date, in: timeZone) : nil
        let desiredIcon = seasonalIcon ?? next.selection
        guard displayedIcon != desiredIcon else { return }
        do {
            try await switcher.apply(desiredIcon)
        } catch {
            if next != previous { repository.saveAppIconSettings(previous) }
            throw error
        }
    }
}
