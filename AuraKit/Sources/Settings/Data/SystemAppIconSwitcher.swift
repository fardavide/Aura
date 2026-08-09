#if canImport(UIKit)
import UIKit
#endif

import SettingsDomain

/// Switches the Home Screen icon through the system, which owns the choice and remembers it
/// across launches — so `current` reads back from it rather than from any stored copy.
///
/// Alternate icons are a UIKit capability with no macOS equivalent. There the composition root
/// leaves the picker out entirely, so the unsupported path below is a backstop, not a screen
/// the user can reach.
@MainActor
public struct SystemAppIconSwitcher: AppIconSwitcher {

    public init() {}

    public var isSupported: Bool {
        #if canImport(UIKit)
        UIApplication.shared.supportsAlternateIcons
        #else
        false
        #endif
    }

    public func current() -> AppIconPreference {
        #if canImport(UIKit)
        guard let name = UIApplication.shared.alternateIconName else { return .halo }
        return AppIconAsset.icon(named: name)
        #else
        return .halo
        #endif
    }

    public func apply(_ icon: AppIconPreference) async throws(SettingsError) {
        #if canImport(UIKit)
        guard isSupported else { throw .iconChangeFailed }
        do {
            try await UIApplication.shared.setAlternateIconName(AppIconAsset.name(for: icon))
        } catch {
            throw .iconChangeFailed
        }
        #else
        throw .iconChangeFailed
        #endif
    }
}
