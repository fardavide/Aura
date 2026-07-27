/// The boundary the Cameras feature depends on to read the user's camera groups. Implemented in
/// the Data layer (the Frigate adapter) — the Domain knows nothing of how it's fetched.
public protocol CameraGroupsRepository: Sendable {
    /// The groups as they change — the current ones first, then each refreshed read. Carries no
    /// error: groups are best-effort chrome, so a failed read emits nothing and the caller keeps
    /// whatever it already had.
    func observeGroups() -> AsyncStream<[CameraGroup]>
}
