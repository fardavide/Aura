import Foundation
import Testing

import CamerasEntities
import CommonFrigate
import CommonNetwork
import TestDoubles
@testable import ExportsData
@testable import ExportsDomain

struct FrigateExportsRepositoryTests {

    @Test func `when reading exports then the library endpoint is called`() async throws {
        // given
        let httpClient = FakeHttpClient(.response(status: 200, body: Data("[]".utf8)))
        let sut = FrigateExportsRepository(config: config, httpClient: httpClient)

        // when
        _ = try await sut.exports()

        // then
        #expect(httpClient.lastRequest?.url?.absoluteString == "http://frigate.local:5000/api/exports")
    }

    @Test func `when reading exports then the wire row maps onto the domain`() async throws {
        // given
        let sut = FrigateExportsRepository(config: config, httpClient: FakeHttpClient(.response(
            status: 200,
            body: Data(payload(inProgress: false).utf8)
        )))

        // when
        let exports = try await sut.exports()

        // then
        #expect(exports.count == 1)
        let export = try #require(exports.first)
        #expect(export.id == ExportId("abc123"))
        #expect(export.camera == CameraName("driveway"))
        #expect(export.name == "driveway_20260918_143012")
        #expect(export.createdAt == Date(timeIntervalSince1970: 1_789_000_000))
        #expect(export.isProcessing == false)
    }

    @Test func `given the server says in progress when reading exports then the export is processing`() async throws {
        // given — readiness is the server's answer, never inferred from elapsed time
        let sut = FrigateExportsRepository(config: config, httpClient: FakeHttpClient(.response(
            status: 200,
            body: Data(payload(inProgress: true).utf8)
        )))

        // when
        let exports = try await sut.exports()

        // then
        #expect(exports.first?.isProcessing == true)
        #expect(exports.first?.isReady == false)
    }

    @Test func `given no in progress flag when reading exports then the export is treated as finished`() async throws {
        // given
        let body = """
        [{"id":"a","camera":"driveway","name":"n","date":1,
          "video_path":"/media/frigate/exports/a.mp4","thumb_path":"/media/frigate/clips/export/a.webp"}]
        """
        let sut = FrigateExportsRepository(config: config, httpClient: FakeHttpClient(.response(
            status: 200, body: Data(body.utf8)
        )))

        // when
        let exports = try await sut.exports()

        // then
        #expect(exports.first?.isProcessing == false)
    }

    @Test(arguments: [
        "/etc/passwd",
        "/media/frigate/../../etc/passwd",
        "/media/frigate/exports/../../../etc/passwd",
        "/media/frigatex/exports/a.mp4",
        "/media/frigate/",
    ])
    func `given a video path outside the media root when reading exports then the row is dropped`(
        videoPath: String
    ) async throws {
        // given — the record is the server's and is treated as untrusted input
        let body = """
        [{"id":"a","camera":"driveway","name":"n","date":1,"in_progress":false,
          "video_path":"\(videoPath)","thumb_path":"/media/frigate/clips/export/a.webp"}]
        """
        let sut = FrigateExportsRepository(config: config, httpClient: FakeHttpClient(.response(
            status: 200, body: Data(body.utf8)
        )))

        // when
        let exports = try await sut.exports()

        // then
        #expect(exports.isEmpty)
    }

    @Test func `given a bad thumbnail path when reading exports then the export survives without a still`() async throws {
        // given — the card has a first-class no-thumbnail variant, so this is not fatal
        let body = """
        [{"id":"a","camera":"driveway","name":"n","date":1,"in_progress":false,
          "video_path":"/media/frigate/exports/a.mp4","thumb_path":"/etc/passwd"}]
        """
        let sut = FrigateExportsRepository(config: config, httpClient: FakeHttpClient(.response(
            status: 200, body: Data(body.utf8)
        )))

        // when
        let exports = try await sut.exports()

        // then
        #expect(exports.count == 1)
        #expect(exports.first?.thumbnailPath == nil)
    }

    @Test func `given malformed json when reading exports then it fails as invalid data`() async {
        // given
        let sut = FrigateExportsRepository(config: config, httpClient: FakeHttpClient(.response(
            status: 200, body: Data("not json".utf8)
        )))

        // when / then
        await #expect(throws: ExportsError.invalidData) { try await sut.exports() }
    }

    @Test(arguments: [
        (401, ExportsError.notAuthorized),
        (403, ExportsError.notAuthorized),
        (400, ExportsError.rejected),
        (500, ExportsError.serverUnavailable),
        (418, ExportsError.unknown),
    ])
    func `given a failing status when reading exports then it maps onto the domain error`(
        statusCode: Int,
        expected: ExportsError
    ) async {
        // given
        let sut = FrigateExportsRepository(config: config, httpClient: FakeHttpClient(.response(
            status: statusCode, body: Data()
        )))

        // when / then
        await #expect(throws: expected) { try await sut.exports() }
    }

    @Test func `given an unreachable server when reading exports then it fails as unreachable`() async {
        // given
        let sut = FrigateExportsRepository(
            config: config,
            httpClient: FakeHttpClient(.failure(URLError(.notConnectedToInternet)))
        )

        // when / then
        await #expect(throws: ExportsError.unreachable) { try await sut.exports() }
    }

    @Test func `when re-reading one export then the by-id endpoint is called`() async throws {
        // given
        let httpClient = FakeHttpClient(.response(status: 200, body: Data(singlePayload.utf8)))
        let sut = FrigateExportsRepository(config: config, httpClient: httpClient)

        // when
        _ = try await sut.export(id: ExportId("abc123"))

        // then
        #expect(httpClient.lastRequest?.url?.absoluteString == "http://frigate.local:5000/api/exports/abc123")
    }

    @Test func `given a refused media path when re-reading one export then it fails as invalid data`() async {
        // given
        let body = """
        {"id":"a","camera":"driveway","name":"n","date":1,"in_progress":false,
         "video_path":"/etc/passwd","thumb_path":"/media/frigate/clips/export/a.webp"}
        """
        let sut = FrigateExportsRepository(config: config, httpClient: FakeHttpClient(.response(
            status: 200, body: Data(body.utf8)
        )))

        // when / then
        await #expect(throws: ExportsError.invalidData) { try await sut.export(id: ExportId("a")) }
    }
}

struct FrigateExportMediaUrlTests {

    @Test func `when resolving a media path then the media root prefix is replaced by the base url`() {
        // given / when
        let url = FrigateExportMediaUrl.media(
            base: config.baseUrl,
            serverPath: "/media/frigate/exports/driveway_a.mp4"
        )

        // then — verified against the v0.17.2 web UI's own baseUrl + path-minus-prefix
        #expect(url?.absoluteString == "http://frigate.local:5000/exports/driveway_a.mp4")
    }

    @Test func `when resolving a clips thumbnail path then it also resolves against the base url`() {
        #expect(
            FrigateExportMediaUrl.media(base: config.baseUrl, serverPath: "/media/frigate/clips/export/a.webp")?
                .absoluteString == "http://frigate.local:5000/clips/export/a.webp"
        )
    }

    @Test(arguments: [
        "/media/frigate/../secrets",
        "/media/frigate/exports/./a.mp4",
        "/media/frigate/exports//a.mp4",
        "/media/frigate",
        "/media/frigate/",
        "exports/a.mp4",
        "",
    ])
    func `given a path that escapes or malforms when resolving then it is refused`(serverPath: String) {
        #expect(FrigateExportMediaUrl.media(base: config.baseUrl, serverPath: serverPath) == nil)
    }
}

struct ExportFileNameTests {

    @Test func `when naming a download then the friendly name carries the path's extension`() {
        // given — the share sheet pre-fills the name the user was just looking at
        #expect(FrigateExportDownloader.fileName(for: export) == "driveway_20260918_143012.mp4")
    }

    @Test func `given an export with no name when naming a download then the path's own basename is used`() {
        // given
        let unnamed = Export(
            id: ExportId("a"),
            camera: CameraName("driveway"),
            name: "",
            createdAt: .now,
            isProcessing: false,
            videoPath: "/media/frigate/exports/driveway_1-2_a.mp4",
            thumbnailPath: nil
        )

        // when / then
        #expect(FrigateExportDownloader.fileName(for: unnamed) == "driveway_1-2_a.mp4")
    }
}

private let config = ServerConfig(
    scheme: .http,
    host: "frigate.local",
    port: 5000,
    username: nil,
    password: nil
)

private let export = Export(
    id: ExportId("abc123"),
    camera: CameraName("driveway"),
    name: "driveway_20260918_143012",
    createdAt: Date(timeIntervalSince1970: 1_789_000_000),
    isProcessing: false,
    videoPath: "/media/frigate/exports/driveway_1-2_abc123.mp4",
    thumbnailPath: "/media/frigate/clips/export/abc123.webp"
)

private func payload(inProgress: Bool) -> String {
    """
    [{"id":"abc123","camera":"driveway","name":"driveway_20260918_143012","date":1789000000,
      "in_progress":\(inProgress),
      "video_path":"/media/frigate/exports/driveway_1-2_abc123.mp4",
      "thumb_path":"/media/frigate/clips/export/abc123.webp"}]
    """
}

private let singlePayload = """
{"id":"abc123","camera":"driveway","name":"driveway_20260918_143012","date":1789000000,
 "in_progress":false,
 "video_path":"/media/frigate/exports/driveway_1-2_abc123.mp4",
 "thumb_path":"/media/frigate/clips/export/abc123.webp"}
"""
