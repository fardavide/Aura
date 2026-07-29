import Foundation
import Testing

import CamerasEntities
import TestDoubles
import TimelineDomain
@testable import TimelinePresentation

/// The Hour-zoom filmstrip's thumbnail cache: past-hour slots render through the clip generator,
/// live-hour slots through the still-frame loader, and everything is cached per (material, slot).
@MainActor
struct RecordingFilmstripStoreTests {

    // MARK: - Completed hours

    @Test
    func `given a clip covering a slot when updated then a thumbnail is generated at the clip offset`() async {
        // given
        let scenario = Scenario(clips: [clip(from: 3600, to: 7200)])

        // when
        await scenario.sut.update(slots: [at(4200)], span: span)

        // then
        #expect(scenario.sut.images[at(4200)] != nil)
        #expect(scenario.generator.sources == [scenario.provider.source])
        #expect(scenario.generator.offsets == [600])
    }

    @Test
    func `given a generated slot when updated again then the cached thumbnail is reused`() async {
        // given
        let scenario = Scenario(clips: [clip(from: 3600, to: 7200)])
        await scenario.sut.update(slots: [at(4200)], span: span)

        // when
        await scenario.sut.update(slots: [at(4200)], span: span)

        // then
        #expect(scenario.generator.offsets == [600])
        #expect(scenario.sut.images[at(4200)] != nil)
    }

    // MARK: - The live hour

    @Test
    func `given no clip and a frame before a slot when updated then the frame's image is loaded`() async throws {
        // given — the in-progress hour has stills but no assembled mp4 yet
        let frame = PreviewFrame(camera: camera, time: at(4190), fileName: "preview_driveway-4190.webp")
        let scenario = Scenario(frames: [frame], frameImage: try onePixelPng())

        // when
        await scenario.sut.update(slots: [at(4200)], span: span)

        // then
        #expect(scenario.sut.images[at(4200)] != nil)
        #expect(scenario.imageLoader.requestedFrames == [frame])
        #expect(scenario.generator.offsets.isEmpty)
    }

    @Test
    func `given a frame rendered slot when its hour completes into a clip then it regenerates from the clip`() async throws {
        // given — the slot's hour was live on the first pass…
        let frame = PreviewFrame(camera: camera, time: at(4190), fileName: "preview_driveway-4190.webp")
        let scenario = Scenario(frames: [frame], frameImage: try onePixelPng())
        await scenario.sut.update(slots: [at(4200)], span: span)

        // when — …and has an assembled mp4 by the next, the live edge having grown meanwhile
        scenario.provider.clipsResult = .success([clip(from: 3600, to: 7200)])
        await scenario.sut.update(slots: [at(4200)], span: TimeRange(start: at(0), end: at(11_100)))

        // then
        #expect(scenario.generator.offsets == [600])
    }

    // MARK: - Material fetching

    @Test
    func `given an unchanged span when updated again then the material is not refetched`() async {
        // given — scrubbing inside a frozen span slides the slots, not the material
        let scenario = Scenario(clips: [clip(from: 3600, to: 7200)])
        await scenario.sut.update(slots: [at(4200)], span: span)

        // when
        await scenario.sut.update(slots: [at(4800)], span: span)

        // then
        #expect(scenario.provider.clipsCallCount == 1)
    }

    @Test
    func `given a failed material fetch when updated again then the fetch is retried`() async {
        // given
        let scenario = Scenario()
        scenario.provider.clipsResult = .failure(.unreachable)
        await scenario.sut.update(slots: [at(4200)], span: span)

        // when — the server is back
        scenario.provider.clipsResult = .success([clip(from: 3600, to: 7200)])
        await scenario.sut.update(slots: [at(4200)], span: span)

        // then
        #expect(scenario.provider.clipsCallCount == 2)
        #expect(scenario.sut.images[at(4200)] != nil)
    }

    // MARK: - No material

    @Test
    func `given no material for a slot when updated then it stays a placeholder and nothing is rendered`() async {
        // given
        let scenario = Scenario()

        // when
        await scenario.sut.update(slots: [at(4200)], span: span)

        // then
        #expect(scenario.sut.images.isEmpty)
        #expect(scenario.generator.offsets.isEmpty)
        #expect(scenario.imageLoader.requestedFrames.isEmpty)
    }

    @Test
    func `given a historical slot in a footage gap when updated then a live hour still is not borrowed`() async {
        // given — every listed frame belongs to the in-progress hour, hours after the slot
        let frame = PreviewFrame(camera: camera, time: at(9500), fileName: "preview_driveway-9500.webp")
        let scenario = Scenario(frames: [frame])

        // when
        await scenario.sut.update(slots: [at(4200)], span: span)

        // then
        #expect(scenario.sut.images[at(4200)] == nil)
        #expect(scenario.imageLoader.requestedFrames.isEmpty)
    }

    // MARK: - Cache bound

    @Test
    func `given a full cache when a new slot is rendered then the slot farthest from the batch is evicted`() async {
        // given
        let scenario = Scenario(clips: [clip(from: 3600, to: 7200)], cacheLimit: 2)
        await scenario.sut.update(slots: [at(3600), at(4200)], span: span)

        // when
        await scenario.sut.update(slots: [at(4800)], span: span)

        // then
        #expect(scenario.sut.images.count == 2)
        #expect(scenario.sut.images[at(3600)] == nil)
        #expect(scenario.sut.images[at(4200)] != nil)
        #expect(scenario.sut.images[at(4800)] != nil)
    }
}

// MARK: - Scenario

@MainActor
private struct Scenario {
    let provider: FakeCameraPreviewProvider
    let generator: FakeFilmstripThumbnailGenerator
    let imageLoader: FakePreviewImageLoader
    let sut: RecordingFilmstripStore

    init(
        clips: [PreviewClip] = [],
        frames: [PreviewFrame] = [],
        frameImage: Data? = nil,
        cacheLimit: Int = 144
    ) {
        provider = FakeCameraPreviewProvider(clips: clips, frames: frames)
        generator = FakeFilmstripThumbnailGenerator()
        imageLoader = FakePreviewImageLoader(image: frameImage)
        sut = RecordingFilmstripStore(
            camera: camera,
            previews: GetCameraPreviews(provider: provider),
            imageLoader: imageLoader,
            generator: generator,
            cacheLimit: cacheLimit
        )
    }
}

private let camera = CameraName("driveway")
private let span = TimeRange(start: at(0), end: at(10_800))

private func clip(from start: TimeInterval, to end: TimeInterval) -> PreviewClip {
    PreviewClip(camera: camera, range: TimeRange(start: at(start), end: at(end)), path: "/preview-\(Int(start)).mp4")
}

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

/// A decodable 1×1 PNG — `platformImage(from:)` rejects arbitrary bytes, so frame images in tests
/// must be real image data.
private func onePixelPng() throws -> Data {
    try #require(Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    ))
}
