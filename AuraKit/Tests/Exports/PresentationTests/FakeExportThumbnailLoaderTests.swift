import Foundation
import Testing

import CamerasEntities
import ExportsDomain
import TestDoubles

struct FakeExportThumbnailLoaderTests {

    @Test func `given configured image bytes when thumbnails are requested concurrently then every request completes with those bytes`() async {
        // given
        let expected = Data([0x89, 0x50, 0x4e, 0x47])
        let scenario = Scenario(data: expected)
        let export = Export(
            id: ExportId("driveway-clip"),
            camera: CameraName("driveway"),
            name: "driveway_20260918_143012",
            createdAt: Date(timeIntervalSince1970: 1_000),
            isProcessing: false,
            videoPath: "/media/frigate/exports/driveway-clip.mp4",
            thumbnailPath: "/media/frigate/exports/driveway-clip.webp"
        )
        let requestCount = 10_000

        // when
        let thumbnails = await withTaskGroup(of: Data?.self) { group in
            for _ in 0..<requestCount {
                group.addTask {
                    await scenario.sut.thumbnail(for: export)
                }
            }
            var results: [Data?] = []
            for await thumbnail in group {
                results.append(thumbnail)
            }
            return results
        }

        // then
        #expect(thumbnails.count == requestCount)
        #expect(thumbnails.allSatisfy { $0 == expected })
    }

    private struct Scenario {
        let sut: FakeExportThumbnailLoader

        init(data: Data) {
            sut = FakeExportThumbnailLoader(data: data)
        }
    }
}
