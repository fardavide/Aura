import Foundation
import Testing

import CamerasDomain
import CamerasEntities
@testable import CamerasData

struct ReviewActivityMappingTests {

    @Test func `given mixed review items when mapping then only in-progress badged severities survive`() throws {
        // given - when - then
        #expect(try decodeActivity().map(\.camera) == [CameraName("front_door"), CameraName("driveway")])
    }

    @Test func `when mapping an alert then its object label and severity are read`() throws {
        // given - when
        let frontDoor = try #require(decodeActivity().first { $0.camera == CameraName("front_door") })

        // then
        #expect(frontDoor.label == "Person")
        #expect(frontDoor.severity == .alert)
    }

    @Test func `when mapping a detection then its object label and severity are read`() throws {
        // given - when
        let driveway = try #require(decodeActivity().first { $0.camera == CameraName("driveway") })

        // then
        #expect(driveway.label == "Car")
        #expect(driveway.severity == .detection)
    }

    @Test func `given a completed item when mapping then it is dropped`() throws {
        // given - when - then
        #expect(try decodeActivity().contains { $0.camera == CameraName("backyard") } == false)
    }

    @Test func `given a significant-motion item when mapping then it is dropped`() throws {
        // given - when - then
        #expect(try decodeActivity().contains { $0.camera == CameraName("garage") } == false)
    }
}

private func decodeActivity() throws -> [CameraActivity] {
    try JSONDecoder().decode([ReviewItemDto].self, from: Data(reviewJson.utf8)).toActiveActivity()
}
