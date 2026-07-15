import Foundation
import Testing

import CamerasDomain
@testable import CamerasData

struct RecordingStorageMappingTests {

    @Test func `given the recordings mount when mapping then its free and total are read as bytes`() throws {
        // given - when
        let storage = try map(stats: statsJson, record: recordConfigJson)

        // then — 1_464_844 MiB free, 1_953_125 MiB total, converted to bytes
        #expect(storage.freeBytes == Int64(1_464_844 * 1_048_576))
        #expect(storage.totalBytes == Int64(1_953_125 * 1_048_576))
    }

    @Test func `given the four retention knobs when mapping then days kept is their max`() throws {
        // given - when
        let storage = try map(stats: statsJson, record: recordConfigJson)

        // then — max(7, 0, 14, 10)
        #expect(storage.retentionDays == 14)
    }

    @Test func `given no recordings mount when mapping then the disk figures are zero`() throws {
        // given
        let stats = """
        { "service": { "storage": { "/tmp/cache": { "total": 1000.0, "used": 100.0, "free": 900.0 } } } }
        """

        // when
        let storage = try map(stats: stats, record: recordConfigJson)

        // then
        #expect(storage.freeBytes == 0)
        #expect(storage.totalBytes == 0)
    }

    @Test func `given all retention knobs are zero when mapping then days kept is nil`() throws {
        // given
        let record = """
        { "record": { "continuous": { "days": 0 }, "motion": { "days": 0 } } }
        """

        // when
        let storage = try map(stats: statsJson, record: record)

        // then
        #expect(storage.retentionDays == nil)
    }
}

private func map(stats: String, record: String) throws -> RecordingStorage {
    let statsDto = try JSONDecoder().decode(StatsDto.self, from: Data(stats.utf8))
    let recordDto = try JSONDecoder().decode(RecordConfigDto.self, from: Data(record.utf8))
    return statsDto.toRecordingStorage(record: recordDto)
}
