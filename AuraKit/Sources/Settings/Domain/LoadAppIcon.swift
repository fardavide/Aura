/// Returns the icon the Home Screen is showing right now.
@MainActor
public struct LoadAppIcon {
    private let switcher: any AppIconSwitcher

    public init(switcher: any AppIconSwitcher) {
        self.switcher = switcher
    }

    public func execute() -> AppIconPreference {
        switcher.current()
    }
}
