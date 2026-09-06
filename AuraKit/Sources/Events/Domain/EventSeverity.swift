/// How Frigate's review classified the period this event belongs to.
public enum EventSeverity: Equatable, Hashable, Sendable, CaseIterable {
    case alert
    case detection
}
