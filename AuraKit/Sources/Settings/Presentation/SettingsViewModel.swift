import Foundation
import Observation

import SettingsDomain

@Observable
@MainActor
public final class SettingsViewModel {
    /// Saved on every change — no explicit save step on the main settings screen.
    public var theme: ThemePreference = .system {
        didSet { saveTheme.execute(theme) }
    }

    private let loadTheme: LoadTheme
    private let saveTheme: SaveTheme

    public init(loadTheme: LoadTheme, saveTheme: SaveTheme) {
        self.loadTheme = loadTheme
        self.saveTheme = saveTheme
    }

    public func onAppear() {
        theme = loadTheme.execute()
    }
}
