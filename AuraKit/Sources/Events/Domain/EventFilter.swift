/// A selectable filter over the loaded events: every event, or one raw Frigate label.
public enum EventFilter: Equatable, Hashable, Sendable, Identifiable {
    case all
    case label(String)

    public var id: String {
        switch self {
        case .all: ""
        case .label(let label): label
        }
    }

    public var title: String {
        switch self {
        case .all: "All"
        case .label(let label): label.capitalized
        }
    }
}
