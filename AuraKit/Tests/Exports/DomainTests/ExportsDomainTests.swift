import Foundation
import Testing

import CamerasEntities
import TestDoubles
@testable import ExportsDomain

struct GetExportsTests {

    @Test func `when getting exports then they are newest first`() async throws {
        // given
        let sut = GetExports(repository: FakeExportsRepository(.success([
            export("older", at: 100),
            export("newer", at: 200),
        ])))

        // when
        let result = try await sut.execute()

        // then
        #expect(result.map(\.id) == [ExportId("newer"), ExportId("older")])
    }

    @Test func `given the server answers out of order when getting exports then the order is still newest first`() async throws {
        // given — the endpoint's own ordering is not trusted; the list promises newest first always
        let sut = GetExports(repository: FakeExportsRepository(.success([
            export("middle", at: 150),
            export("newest", at: 300),
            export("oldest", at: 50),
        ])))

        // when
        let result = try await sut.execute()

        // then
        #expect(result.map(\.id) == [ExportId("newest"), ExportId("middle"), ExportId("oldest")])
    }

    @Test func `given an unreachable server when getting exports then it fails`() async {
        // given
        let sut = GetExports(repository: FakeExportsRepository(.failure(.unreachable)))

        // when / then
        await #expect(throws: ExportsError.unreachable) { try await sut.execute() }
    }
}

struct GetExportTests {

    @Test func `when re-reading one export then the repository is asked for that id`() async throws {
        // given
        let repository = FakeExportsRepository(.success([]), singleExport: .success(export("a", at: 10)))
        let sut = GetExport(repository: repository)

        // when
        _ = try await sut.execute(id: ExportId("a"))

        // then
        #expect(repository.requestedIds == [ExportId("a")])
    }
}

struct ExportCollectionsTests {

    @Test func `when grouping by day then the newest day comes first`() {
        // given
        let exports = [
            export("mon", at: day(1, hour: 9)),
            export("tue", at: day(2, hour: 9)),
        ]

        // when
        let groups = exports.groupedByDay(calendar: gmtCalendar)

        // then
        #expect(groups.map { $0.exports.map(\.id) } == [[ExportId("tue")], [ExportId("mon")]])
    }

    @Test func `given several clips on one day when grouping then the newest clip comes first`() {
        // given
        let exports = [
            export("morning", at: day(1, hour: 7)),
            export("evening", at: day(1, hour: 20)),
            export("noon", at: day(1, hour: 12)),
        ]

        // when
        let groups = exports.groupedByDay(calendar: gmtCalendar)

        // then
        #expect(groups.count == 1)
        #expect(groups[0].exports.map(\.id) == [ExportId("evening"), ExportId("noon"), ExportId("morning")])
    }

    @Test func `given no exports when grouping then there are no groups`() {
        #expect([Export]().groupedByDay(calendar: gmtCalendar).isEmpty)
    }

    @Test func `when summarising then clips are counted by row and cameras by distinct name`() {
        // given
        let exports = [
            export("a", at: 10, camera: "driveway"),
            export("b", at: 20, camera: "driveway"),
            export("c", at: 30, camera: "garage"),
        ]

        // when
        let summary = exports.summary

        // then
        #expect(summary == ExportsSummary(clipCount: 3, cameraCount: 2))
    }
}

struct ExportReadinessTests {

    @Test func `given a processing export then it is not ready`() {
        #expect(export("a", at: 10, isProcessing: true).isReady == false)
    }

    @Test func `given a finished export then it is ready`() {
        #expect(export("a", at: 10).isReady)
    }
}

struct ExportTransferTests {

    @Test func `given an unknown length when reading the fraction then there is none`() {
        #expect(ExportTransfer(bytesReceived: 100, bytesExpected: nil).fraction == nil)
    }

    @Test func `given a zero length when reading the fraction then there is none`() {
        // given — a zero-length body would otherwise divide by zero
        #expect(ExportTransfer(bytesReceived: 0, bytesExpected: 0).fraction == nil)
    }

    @Test func `when reading the fraction then it is received over expected`() {
        #expect(ExportTransfer(bytesReceived: 25, bytesExpected: 100).fraction == 0.25)
    }

    @Test func `given more bytes than the server declared when reading the fraction then it is clamped to full`() {
        // given — an under-reported length must not drive the bar past 100%
        #expect(ExportTransfer(bytesReceived: 150, bytesExpected: 100).fraction == 1)
    }
}

struct DownloadExportTests {

    @Test func `given a processing export when downloading then it is refused without asking the server`() async {
        // given
        let downloader = FakeExportDownloader()
        let sut = DownloadExport(downloader: downloader)
        let processing = export("a", at: 10, isProcessing: true)

        // when / then
        await #expect(throws: ExportsError.rejected) {
            try await sut.execute(processing) { _ in }
        }
        #expect(downloader.downloaded.isEmpty)
    }

    @Test func `given a ready export when downloading then progress is reported as the bytes arrive`() async throws {
        // given
        let downloader = FakeExportDownloader(steps: [
            ExportTransfer(bytesReceived: 50, bytesExpected: 100),
            ExportTransfer(bytesReceived: 100, bytesExpected: 100),
        ])
        let sut = DownloadExport(downloader: downloader)
        let reported = Reported()

        // when
        _ = try await sut.execute(export("a", at: 10)) { reported.append($0) }

        // then
        #expect(reported.fractions == [0.5, 1])
    }

    @Test func `when discarding a download then the temporary file is handed back for deletion`() async throws {
        // given
        let downloader = FakeExportDownloader()
        let sut = DownloadExport(downloader: downloader)

        // when
        let downloaded = try await sut.execute(export("a", at: 10)) { _ in }
        sut.discard(downloaded)

        // then
        #expect(downloader.discarded == [downloaded])
    }
}

/// Collects the progress callback's values across the concurrency boundary the protocol declares.
private final class Reported: @unchecked Sendable {
    private var transfers: [ExportTransfer] = []

    func append(_ transfer: ExportTransfer) {
        transfers.append(transfer)
    }

    var fractions: [Double?] { transfers.map(\.fraction) }
}

private func export(
    _ id: String,
    at epoch: TimeInterval,
    camera: String = "driveway",
    isProcessing: Bool = false
) -> Export {
    Export(
        id: ExportId(id),
        camera: CameraName(camera),
        name: "\(camera)_20260918_143012",
        createdAt: Date(timeIntervalSince1970: epoch),
        isProcessing: isProcessing,
        videoPath: "/media/frigate/exports/\(id).mp4",
        thumbnailPath: "/media/frigate/exports/\(id).webp"
    )
}

/// Epoch seconds for a given day-of-January and hour, GMT — so the day boundaries these tests
/// assert on never depend on the machine's time zone.
private func day(_ day: Int, hour: Int) -> TimeInterval {
    gmtCalendar.date(from: DateComponents(year: 2026, month: 1, day: day, hour: hour))!
        .timeIntervalSince1970
}

private let gmtCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}()
