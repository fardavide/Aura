import Foundation
import Testing

@testable import CommonFrigate

struct ServerConfigTests {

    @Test func `when reading the base url then it composes scheme host and port`() {
        // given
        let config = ServerConfig(
            scheme: .http,
            host: "frigate.local",
            port: 5000,
            username: nil,
            password: nil
        )

        // then
        #expect(config.baseUrl == URL(string: "http://frigate.local:5000")!)
    }

    @Test func `given the https scheme when reading the base url then it uses https`() {
        // given
        let config = ServerConfig(
            scheme: .https,
            host: "cam.example.com",
            port: 8971,
            username: nil,
            password: nil
        )

        // then
        #expect(config.baseUrl == URL(string: "https://cam.example.com:8971")!)
    }
}

struct FrigateUrlTests {
    private let base = URL(string: "http://frigate.local:5000")!

    @Test func `when building the config endpoint then it targets api config`() {
        #expect(
            FrigateEndpoint.config.url(base: base)
                == URL(string: "http://frigate.local:5000/api/config")!
        )
    }

    @Test func `when building the latest image url then it appends camera and height`() {
        // given - when
        let url = FrigateMediaUrl.latestImage(base: base, camera: "driveway", height: 320)

        // then
        #expect(url == URL(string: "http://frigate.local:5000/api/driveway/latest.jpg?height=320")!)
    }

    @Test func `when building the live stream url then it proxies go2rtc through Frigate`() {
        #expect(
            FrigateLiveUrl.stream(base: base, src: "driveway")
                == URL(string: "http://frigate.local:5000/api/go2rtc/api/stream.m3u8?src=driveway")!
        )
    }

    @Test func `when building the events endpoint then it includes the limit`() {
        #expect(
            FrigateEndpoint.events(limit: 50).url(base: base)
                == URL(string: "http://frigate.local:5000/api/events?limit=50")!
        )
    }

    @Test func `when building event media urls then they target the event`() {
        #expect(
            FrigateMediaUrl.thumbnail(base: base, eventId: "ev1")
                == URL(string: "http://frigate.local:5000/api/events/ev1/thumbnail.jpg")!
        )
        #expect(
            FrigateMediaUrl.clip(base: base, eventId: "ev1")
                == URL(string: "http://frigate.local:5000/api/events/ev1/clip.mp4")!
        )
    }

    @Test func `when building review timeline urls then they target review and recordings`() {
        #expect(
            FrigateReviewUrl.review(base: base, after: 100, before: 200)
                == URL(string: "http://frigate.local:5000/api/review?after=100&before=200")!
        )
        #expect(
            FrigateReviewUrl.motionActivity(base: base, after: 100, before: 200, scale: 30)
                == URL(string: "http://frigate.local:5000/api/review/activity/motion?after=100&before=200&scale=30")!
        )
        #expect(
            FrigateReviewUrl.recordingsUnavailable(base: base, after: 100, before: 200, scale: 30)
                == URL(string: "http://frigate.local:5000/api/recordings/unavailable?after=100&before=200&scale=30")!
        )
    }

    @Test func `when building the preview clip list then it rounds the range under api preview`() {
        #expect(
            FrigatePreviewUrl.clipList(base: base, camera: "all", after: 100.6, before: 200.4)
                == URL(string: "http://frigate.local:5000/api/preview/all/start/101/end/200")!
        )
    }

    @Test func `when building the preview frame list then it floors the start and ceils the end`() {
        #expect(
            FrigatePreviewUrl.frameList(base: base, camera: "driveway", after: 100.6, before: 200.4)
                == URL(string: "http://frigate.local:5000/api/preview/driveway/start/100/end/201/frames")!
        )
    }

    @Test func `when building a preview frame thumbnail then it targets the webp`() {
        #expect(
            FrigatePreviewUrl.frameThumbnail(base: base, fileName: "preview_driveway-123.webp")
                == URL(string: "http://frigate.local:5000/api/preview/preview_driveway-123.webp/thumbnail.webp")!
        )
    }

    @Test func `when resolving clip media then it drops the leading slash onto the base`() {
        #expect(
            FrigatePreviewUrl.clipMedia(base: base, path: "/clips/previews/driveway-1.mp4")
                == URL(string: "http://frigate.local:5000/clips/previews/driveway-1.mp4")!
        )
    }
}
