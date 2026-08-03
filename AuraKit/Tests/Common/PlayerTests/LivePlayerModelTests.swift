import Foundation
import SwiftUI
import Testing

import CommonPlayer

@MainActor
struct LivePlayerModelTests {

    // MARK: Returning from the background

    @Test func `given a playing stream when the app returns from the background then it plays a fresh live item`() {
        // given
        let sut = liveModel()
        sut.start()
        let stale = sut.player.currentItem

        // when
        sut.handleScenePhase(.background)
        sut.handleScenePhase(.inactive)
        sut.handleScenePhase(.active)

        // then
        #expect(sut.player.currentItem !== stale)
        #expect(sut.isPlaying)
    }

    @Test func `given a playing stream when the app only loses focus then it keeps the live item`() {
        // given
        let sut = liveModel()
        sut.start()
        let item = sut.player.currentItem

        // when
        sut.handleScenePhase(.inactive)
        sut.handleScenePhase(.active)

        // then
        #expect(sut.player.currentItem === item)
        #expect(sut.isPlaying)
    }

    @Test func `given a paused stream when the app returns from the background then it stays paused on the same item`() {
        // given
        let sut = liveModel()
        sut.start()
        sut.togglePlayPause()
        let item = sut.player.currentItem

        // when
        sut.handleScenePhase(.background)
        sut.handleScenePhase(.active)

        // then
        #expect(sut.player.currentItem === item)
        #expect(sut.isPlaying == false)
    }

    // MARK: Resuming from pause

    @Test func `given a stream paused across a background when playing again then it plays a fresh live item`() {
        // given
        let sut = liveModel()
        sut.start()
        sut.togglePlayPause()
        sut.handleScenePhase(.background)
        sut.handleScenePhase(.active)
        let stale = sut.player.currentItem

        // when
        sut.togglePlayPause()

        // then
        #expect(sut.player.currentItem !== stale)
        #expect(sut.isPlaying)
    }

    @Test func `given a stream paused with the app in the foreground when playing again then it keeps the live item`() {
        // given
        let sut = liveModel()
        sut.start()
        sut.togglePlayPause()
        let item = sut.player.currentItem

        // when
        sut.togglePlayPause()

        // then
        #expect(sut.player.currentItem === item)
        #expect(sut.isPlaying)
    }
}

@MainActor
private func liveModel() -> LivePlayerModel {
    LivePlayerModel(
        url: URL(string: "http://frigate.test:1984/api/stream.m3u8?src=driveway")!,
        headers: ["Authorization": "Basic ZHJpdmV3YXk="]
    )
}
