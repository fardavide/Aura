import Foundation
import Testing

import CamerasEntities
import TestDoubles
@testable import ExportsDomain

struct CreateExportTests {

    @Test func `given a camera and a range when creating then the server is asked for exactly those bounds`() async throws {
        // given
        let repository = FakeExportsRepository(.success([]), createdId: .success(ExportId("new")))
        let sut = CreateExport(repository: repository)

        // when
        _ = try await sut.execute(camera: CameraName("driveway"), from: at(1_000), to: at(1_090))

        // then
        #expect(repository.creationRequests.count == 1)
        #expect(repository.creationRequests.first?.camera == CameraName("driveway"))
        #expect(repository.creationRequests.first?.from == at(1_000))
        #expect(repository.creationRequests.first?.to == at(1_090))
    }

    @Test func `given the server accepts then the new export id is returned`() async throws {
        let repository = FakeExportsRepository(.success([]), createdId: .success(ExportId("export-7")))
        let sut = CreateExport(repository: repository)

        #expect(try await sut.execute(camera: CameraName("drive"), from: at(0), to: at(10)) == ExportId("export-7"))
    }

    /// The route accepts floats but the handler converts the bounds to integers before exporting,
    /// so the client submits what the server will actually use — otherwise the readout and the
    /// resulting file disagree about where the clip starts.
    @Test func `given fractional bounds then whole seconds are submitted`() async throws {
        let repository = FakeExportsRepository(.success([]), createdId: .success(ExportId("new")))
        let sut = CreateExport(repository: repository)

        _ = try await sut.execute(camera: CameraName("drive"), from: at(1_000.8), to: at(1_090.2))

        #expect(repository.creationRequests.first?.from == at(1_000))
        #expect(repository.creationRequests.first?.to == at(1_090))
    }

    @Test func `given the server refuses the range then the failure is a rejection`() async {
        let repository = FakeExportsRepository(.success([]), createdId: .failure(.rejected))
        let sut = CreateExport(repository: repository)

        await #expect(throws: ExportsError.rejected) {
            try await sut.execute(camera: CameraName("drive"), from: at(0), to: at(10))
        }
    }

    @Test func `given the server cannot be reached then the failure is a transport one`() async {
        let repository = FakeExportsRepository(.success([]), createdId: .failure(.unreachable))
        let sut = CreateExport(repository: repository)

        await #expect(throws: ExportsError.unreachable) {
            try await sut.execute(camera: CameraName("drive"), from: at(0), to: at(10))
        }
    }
}

struct ExportsErrorRetryTests {

    @Test func `given a rejection then retrying the same request is pointless`() {
        #expect(!ExportsError.rejected.isRetryable)
    }

    @Test func `given a transport failure then it is worth retrying`() {
        #expect(ExportsError.unreachable.isRetryable)
        #expect(ExportsError.serverUnavailable.isRetryable)
        #expect(ExportsError.unknown.isRetryable)
    }

    @Test func `given bad credentials or an unreadable answer then retrying changes nothing`() {
        #expect(!ExportsError.notAuthorized.isRetryable)
        #expect(!ExportsError.invalidData.isRetryable)
    }
}

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }
