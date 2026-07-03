import SwiftUI
import Testing

import CamerasDomain
import CamerasPresentation

/// Screenshot tests for the camera grid screen across its states, captured on every device +
/// orientation (iOS). Tiles are pinned to the placeholder (no preview image, no live video) so
/// the grid renders the same pixels on every run.
@MainActor
struct CameraGridSnapshotTests {

    @Test func `given cameras when loaded then it matches the reference`() async {
        // given
        let view = await cameraGridScreen(cameras: .success(snapshotCameras()))

        // then
        assertScreenSnapshot(view, named: "loaded")
    }

    @Test func `given no cameras when empty then it matches the reference`() async {
        // given
        let view = await cameraGridScreen(cameras: .success([]))

        // then
        assertScreenSnapshot(view, named: "empty")
    }

    @Test func `given a server failure when failed then it matches the reference`() async {
        // given
        let view = await cameraGridScreen(cameras: .failure(.serverUnavailable))

        // then
        assertScreenSnapshot(view, named: "failed")
    }
}

// MARK: - View builder

/// The camera grid screen, driven to a terminal state before rendering so the view's own
/// `.task` re-load settles on the same pixels. Preview images resolve to `nil`, pinning every
/// tile to the deterministic placeholder.
@MainActor
private func cameraGridScreen(cameras: Result<[Camera], CamerasError>) async -> some View {
    let viewModel = CameraGridViewModel(
        getCameras: GetCameras(repository: FakeCameras(cameras)),
        imageLoader: NoPreviewImages()
    )
    await viewModel.load()

    return CameraGridView(
        viewModel: viewModel,
        onOpenSettings: {},
        makeDetailViewModel: { CameraDetailViewModel(camera: $0, streamProvider: NoStreams()) }
    )
}

// MARK: - Fakes

/// No preview material — every tile renders the placeholder.
private struct NoPreviewImages: CameraImageLoading {
    func previewImage(for camera: CameraName) async -> Data? { nil }
}

/// Unused: the detail factory is never invoked in a grid snapshot (no navigation happens).
private struct NoStreams: CameraStreamProviding {
    func streamSource(for camera: Camera) -> CameraStreamSource? { nil }
}
