import Foundation
import Observation

import SettingsDomain

@Observable
@MainActor
public final class AppIconViewModel {
    public private(set) var selection: AppIconPreference
    public private(set) var usesSeasonalIcons: Bool
    public private(set) var displayedIcon: AppIconPreference
    public private(set) var isUpdating = false
    public private(set) var errorMessage: String?

    private let loadAppIcon: LoadAppIcon
    private let changeAppIcon: ChangeAppIcon
    private let now: () -> Date
    private let timeZone: () -> TimeZone

    public init(
        loadAppIcon: LoadAppIcon,
        changeAppIcon: ChangeAppIcon,
        now: @escaping () -> Date,
        timeZone: @escaping () -> TimeZone
    ) {
        self.loadAppIcon = loadAppIcon
        self.changeAppIcon = changeAppIcon
        self.now = now
        self.timeZone = timeZone
        let state = loadAppIcon.execute()
        selection = state.settings.selection
        usesSeasonalIcons = state.settings.usesSeasonalIcons
        displayedIcon = state.displayed
    }

    public func refresh() async {
        await update(.refresh)
    }

    public func select(_ icon: AppIconPreference) async {
        guard icon != selection else { return }
        await update(.select(icon))
    }

    public func setSeasonalIcons(_ isEnabled: Bool) async {
        guard isEnabled != usesSeasonalIcons else { return }
        await update(.setSeasonalIcons(isEnabled))
    }

    private func update(_ request: ChangeAppIcon.Request) async {
        guard !isUpdating else { return }
        isUpdating = true
        errorMessage = nil
        do {
            try await changeAppIcon.execute(request, at: now(), in: timeZone())
        } catch {
            errorMessage = "Couldn't change the icon. Try again."
        }
        let state = loadAppIcon.execute()
        selection = state.settings.selection
        usesSeasonalIcons = state.settings.usesSeasonalIcons
        displayedIcon = state.displayed
        isUpdating = false
    }
}
