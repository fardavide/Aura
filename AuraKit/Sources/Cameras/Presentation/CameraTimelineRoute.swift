import CamerasDomain

/// The push from a camera's live stream to that camera's recordings.
///
/// The destination is a Timeline screen, but the Cameras vertical doesn't build it: the grid takes
/// the destination as an injected view builder and the composition root supplies it, so a link
/// across features costs no dependency between them.
struct CameraTimelineRoute: Hashable {
    let camera: Camera
}
