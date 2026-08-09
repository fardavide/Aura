import Observation

import SettingsDomain

@Observable
@MainActor
public final class AppIconViewModel {
    /// Moves to the tapped icon straight away so the tick follows the finger, and moves back
    /// if the system refuses the change — hence read-only from the view.
    public private(set) var selection: AppIconPreference = .halo
    public private(set) var errorMessage: String?

    private let loadAppIcon: LoadAppIcon
    private let changeAppIcon: ChangeAppIcon

    public init(loadAppIcon: LoadAppIcon, changeAppIcon: ChangeAppIcon) {
        self.loadAppIcon = loadAppIcon
        self.changeAppIcon = changeAppIcon
    }

    public func onAppear() {
        selection = loadAppIcon.execute()
    }

    public func select(_ icon: AppIconPreference) async {
        guard icon != selection else { return }
        let previous = selection
        selection = icon
        errorMessage = nil
        do {
            try await changeAppIcon.execute(icon)
        } catch {
            selection = previous
            errorMessage = "Couldn't change the icon. Try again."
        }
    }
}
