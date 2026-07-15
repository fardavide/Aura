import Foundation
import Testing

import CamerasDomain
import CamerasEntities
@testable import CamerasData

struct GroupsConfigMappingTests {

    @Test func `given an array membership when mapping then the camera names are read`() throws {
        // given - when
        let outdoor = try #require(decodeGroups().first { $0.name == "Outdoor" })

        // then
        #expect(outdoor.cameraNames == [CameraName("driveway"), CameraName("front_door")])
    }

    @Test func `given a comma-joined membership when mapping then it is split into camera names`() throws {
        // given - when
        let indoor = try #require(decodeGroups().first { $0.name == "Indoor" })

        // then
        #expect(indoor.cameraNames == [CameraName("kitchen"), CameraName("garage")])
    }

    @Test func `given a birdseye-only group when mapping then birdseye is stripped leaving it empty`() throws {
        // given - when
        let overview = try #require(decodeGroups().first { $0.name == "Overview" })

        // then
        #expect(overview.cameraNames.isEmpty)
    }

    @Test func `when mapping then each group's order is read`() throws {
        // given - when
        let groups = try decodeGroups()

        // then
        #expect(groups.first { $0.name == "Outdoor" }?.order == 1)
        #expect(groups.first { $0.name == "Indoor" }?.order == 0)
    }

    @Test func `given no camera_groups key when mapping then there are no groups`() throws {
        // given - when
        let groups = try JSONDecoder()
            .decode(GroupsConfigDto.self, from: Data(configJson.utf8))
            .toCameraGroups()

        // then
        #expect(groups.isEmpty)
    }
}

private func decodeGroups() throws -> [CameraGroup] {
    try JSONDecoder().decode(GroupsConfigDto.self, from: Data(groupsConfigJson.utf8)).toCameraGroups()
}
