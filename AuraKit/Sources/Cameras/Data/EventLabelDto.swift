/// The one field of a `GET /api/events` element the grid's "today" tally needs. Kept local to the
/// Cameras vertical (like `ReviewItemDto`) rather than depending on the Events feature. Internal —
/// it never leaves the Data layer.
struct EventLabelDto: Decodable {
    let label: String
}
