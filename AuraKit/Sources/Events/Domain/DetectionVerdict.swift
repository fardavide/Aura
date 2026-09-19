/// What the user can tell the server about a detection: the object it named was right, or it was
/// not. There is deliberately no "it was actually a cat" case — the upstream API carries a verdict
/// on the label it chose and nothing else, so suggesting the right one happens on the training site.
public enum DetectionVerdict: Equatable, Sendable {
    case correct
    case incorrect
}
