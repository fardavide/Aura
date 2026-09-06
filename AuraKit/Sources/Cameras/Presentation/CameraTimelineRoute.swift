import CamerasDomain

/// The push from a camera's live stream to that camera's recordings.
///
/// The destination is a Timeline screen, but the Cameras vertical doesn't build it: the grid takes
/// the destination as an injected view builder and the composition root supplies it, so a link
/// across features costs no dependency between them. Public so `AuraTests` (importing
/// `CamerasPresentation` normally, not `@testable`) can register a stub `navigationDestination` for
/// its own `NavigationStack` — otherwise a value-based `NavigationLink` whose type has no
/// destination in scope renders disabled, which would bake an inoperable Timeline button into
/// every snapshot baseline.
public struct CameraTimelineRoute: Hashable {
    public let camera: Camera

    public init(camera: Camera) {
        self.camera = camera
    }
}
