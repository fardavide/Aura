import Foundation
import Testing

import CamerasEntities
import CommonFrigate
import TestDoubles
import TimelineDomain
@testable import TimelineData

struct RecordingClipsTests {
    @Test func `given mapped recording clips when fetching then file offsets durations and auth are retained`() async throws {
        // given
        let scenario = Scenario(body: """
        {"durations":[8500,10016],"sequences":[{"clips":[
          {"type":"source","path":"/media/frigate/recordings/1970-01-01/00/driveway/59.58.mp4","clipFrom":1500},
          {"type":"source","path":"/media/frigate/recordings/1970-01-01/01/driveway/00.08.mp4"}
        ]}]}
        """)

        // when
        let clips = try await scenario.sut.clips(for: CameraName("driveway"), in: TimeRange(
            start: Date(timeIntervalSince1970: 3600), end: Date(timeIntervalSince1970: 3720)
        ))

        // then
        #expect(clips.count == 2)
        #expect(clips.first?.source.url == URL(string: "http://frigate.test:5000/recordings/1970-01-01/00/driveway/59.58.mp4"))
        #expect(clips.first?.sourceOffset == 1.5)
        #expect(clips.map(\.duration) == [8.5, 10.016])
        #expect(clips.first?.source.headers["Authorization"] == "Basic dTpw")
        #expect(scenario.http.lastRequest?.url == URL(string: "http://frigate.test:5000/api/vod/driveway/start/3600/end/3720"))
    }

    @Test func `given a tiny head overlap retained by keyframe preroll when fetching then the head is discarded and the next clip is retained`() async throws {
        // given
        let scenario = Scenario(body: """
        {"durations":[2050,10000],"sequences":[{"clips":[
          {"type":"source","path":"/media/frigate/recordings/1970-01-01/00/driveway/59.50.mp4","clipFrom":8000},
          {"type":"source","path":"/media/frigate/recordings/1970-01-01/01/driveway/00.00.mp4"}
        ]}]}
        """, recordingsBody: """
        [{"start_time":3590,"end_time":3600.05,"duration":10.05},
         {"start_time":3600.05,"end_time":3610.05,"duration":10}]
        """)

        // when
        let clips = try await scenario.sut.clips(for: CameraName("driveway"), in: TimeRange(
            start: Date(timeIntervalSince1970: 3600), end: Date(timeIntervalSince1970: 3720)
        ))

        // then
        #expect(clips.count == 1)
        let clip = try #require(clips.first)
        #expect(clip.range == TimeRange(
            start: Date(timeIntervalSince1970: 3600.05), end: Date(timeIntervalSince1970: 3610.05)
        ))
        #expect(clip.duration == 10)
        #expect(clip.sourceOffset == 0)
        #expect(clip.source.url == URL(string: "http://frigate.test:5000/recordings/1970-01-01/01/driveway/00.00.mp4"))
    }

    private struct Scenario {
        let http: FakeHttpClient
        let sut: FrigateCameraRecordingsRepository

        init(body: String) {
            self.init(body: body, recordingsBody: """
            [{"start_time":3598.5,"end_time":3608.5,"duration":10},
             {"start_time":3608.5,"end_time":3618.516,"duration":10.016}]
            """)
        }

        init(body: String, recordingsBody: String) {
            http = FakeHttpClient(routes: [
                ("api/vod/", .response(status: 200, body: Data(body.utf8))),
                ("/recordings?", .response(status: 200, body: Data(recordingsBody.utf8))),
            ])
            sut = FrigateCameraRecordingsRepository(
                config: ServerConfig(scheme: .http, host: "frigate.test", port: 5000, username: "u", password: "p"),
                httpClient: http
            )
        }
    }
}
