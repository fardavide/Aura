/// Platform boundary for the Home Screen icon, implemented in the Data layer.
///
/// The system owns the current choice and remembers it across launches, so this reads through
/// to it rather than keeping a copy — there is no second value to drift out of step. Bound to
/// the main actor because changing an app's icon is a UI side effect.
@MainActor
public protocol AppIconSwitcher {
    /// `false` where the platform has no swappable icon. The picker is left out of Settings
    /// entirely in that case, rather than offered and then failing on every tap.
    var isSupported: Bool { get }
    func current() -> AppIconPreference
    func apply(_ icon: AppIconPreference) async throws(SettingsError)
}
