import Testing

@testable import CamerasDomain

struct CamerasDomainTests {

    // MARK: CameraName

    @Test func `when comparing camera names with the same value then they are equal`() {
        // given - when
        let a = CameraName("driveway")
        let b = CameraName("driveway")

        // then
        #expect(a == b)
    }

    @Test func `when sorting camera names then they are ordered by value`() {
        // given - when
        let sorted = [CameraName("garage"), CameraName("driveway")].sorted()

        // then
        #expect(sorted == [CameraName("driveway"), CameraName("garage")])
    }

    // MARK: GetCameras

    @Test func `given a disabled camera when getting cameras then it is excluded`() async throws {
        // given
        let getCameras = GetCameras(repository: StubCamerasRepository([
            camera("driveway", isEnabled: true),
            camera("garage", isEnabled: false),
        ]))

        // when
        let result = try await getCameras.execute()

        // then
        #expect(result.map(\.name) == [CameraName("driveway")])
    }
}

private func camera(_ name: String, isEnabled: Bool) -> Camera {
    Camera(name: CameraName(name), friendlyName: nil, isEnabled: isEnabled, streamNames: [])
}

private final class StubCamerasRepository: CamerasRepository {
    private let stubbed: [Camera]
    init(_ stubbed: [Camera]) { self.stubbed = stubbed }
    func cameras() async throws(CamerasError) -> [Camera] { stubbed }
}
