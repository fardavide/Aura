/// The Home Screen icon the user has chosen. `halo` is the icon the app ships with; the rest
/// are alternates offered in Settings, and the order here is the order they are offered in.
public enum AppIconPreference: String, Sendable, CaseIterable {
    case halo
    case heavy
    case thin
    case sweep
    case aurora
    case signal
    case daylight
}
