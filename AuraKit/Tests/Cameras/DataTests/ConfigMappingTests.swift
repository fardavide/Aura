import Foundation
import Testing

import CamerasDomain
import CamerasEntities
@testable import CamerasData

struct ConfigMappingTests {

    @Test func `when mapping config then name friendly name and streams are read`() throws {
        // given - when
        let driveway = try #require(decodeConfig().first { $0.name == CameraName("driveway") })

        // then
        #expect(driveway.friendlyName == "Driveway")
        #expect(driveway.isEnabled == true)
        #expect(driveway.streamNames == ["driveway", "driveway_sub"])
    }

    @Test func `given no enabled field when mapping config then the camera is enabled`() throws {
        // given - when
        let porch = try #require(decodeConfig().first { $0.name == CameraName("porch") })

        // then
        #expect(porch.isEnabled == true)
        #expect(porch.friendlyName == "Front Porch")
        #expect(porch.streamNames == [])
    }

    @Test func `given a disabled camera when mapping config then it is still mapped`() throws {
        // given - when
        let garage = try #require(decodeConfig().first { $0.name == CameraName("garage") })

        // then
        #expect(garage.isEnabled == false)
        #expect(garage.friendlyName == nil)
    }

    @Test func `when mapping config then cameras are sorted by name`() throws {
        // given - when - then
        #expect(
            try decodeConfig().map(\.name)
                == [CameraName("driveway"), CameraName("garage"), CameraName("porch")]
        )
    }
}

private func decodeConfig() throws -> [Camera] {
    try JSONDecoder().decode(ConfigDto.self, from: Data(configJson.utf8)).toCameras()
}
