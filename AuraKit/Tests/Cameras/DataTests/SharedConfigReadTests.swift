import Foundation
import Testing

import CamerasDomain
import CommonFrigate
import CommonNetwork
import TestDoubles
@testable import CamerasData

/// The point of the shared config provider: the three Cameras reads that each need a slice of
/// `/api/config` cost **one** request between them, not one apiece.
struct SharedConfigReadTests {

    @Test func `given the three config readers when a screen loads then the config is read once`() async throws {
        // given
        let http = FakeHttpClient(routes: [
            ("api/stats", .response(status: 200, body: Data(statsJson.utf8))),
            ("api/config", .response(status: 200, body: Data(fullConfigJson.utf8))),
        ])
        let provider = FrigateConfigProvider(
            config: .test, httpClient: http, refreshInterval: .seconds(120)
        )
        let cameras = FrigateCamerasRepository(configProvider: provider)
        let groups = FrigateCameraGroupsRepository(configProvider: provider)
        let storage = FrigateRecordingStorageRepository(
            config: .test, httpClient: http, configProvider: provider
        )

        // when — the order the grid loads them in: camera list first, then the summary chrome
        _ = try await cameras.cameras()
        var groupsStream = groups.observeGroups().makeAsyncIterator()
        _ = await groupsStream.next()
        var storageStream = storage.observeStorage().makeAsyncIterator()
        _ = await storageStream.next()

        // then
        #expect(configRequestCount(http) == 1)
    }

    private func configRequestCount(_ http: FakeHttpClient) -> Int {
        http.requestedUrls.filter { $0.contains("api/config") }.count
    }
}

/// One `/api/config` body carrying every slice the three readers decode.
private let fullConfigJson = """
{
  "cameras": {
    "driveway": { "enabled": true, "live": { "streams": { "Driveway": "driveway" } } }
  },
  "camera_groups": {
    "Outdoor": { "cameras": ["driveway"], "order": 0 }
  },
  "record": {
    "enabled": true,
    "continuous": { "days": 7 },
    "alerts": { "retain": { "days": 14 } }
  }
}
"""
