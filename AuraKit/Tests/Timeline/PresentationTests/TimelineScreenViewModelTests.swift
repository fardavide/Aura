import Foundation
import Observation
import Testing

import CamerasDomain
import CamerasEntities
import SettingsDomain
import TestDoubles
import TimelineDomain
@testable import TimelinePresentation

// The hero-selection and alert-badge slice of `TimelineScreenViewModel` — kept apart from
// `TimelinePresentationTests.swift`'s own `TimelineScreenViewModelTests` (load/refresh/ordering)
// so neither file has to guess the other's naming.

@MainActor
struct TimelineHeroCameraTests {

    @Test func `given an alert active at the scrub instant when loaded then its camera is the hero`() async {
        // given
        let timeline = DayTimeline(markers: [alertMarker(camera: frontDoor, start: at(999_990), end: nil)], motion: [], gaps: [])
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.heroCamera?.name == frontDoor.name)
    }

    @Test func `given no alert at the scrub instant when loaded then the first camera is the hero`() async {
        // given
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: emptyTimeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.heroCamera?.name == driveway.name)
    }

    @Test func `given two alerts active at the instant when loaded then the most recently started camera is the hero`() async {
        // given
        let timeline = DayTimeline(
            markers: [
                alertMarker(camera: driveway, start: at(999_950), end: nil),
                alertMarker(camera: frontDoor, start: at(999_980), end: nil),
            ],
            motion: [], gaps: []
        )
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.heroCamera?.name == frontDoor.name)
    }

    @Test func `given an alert that ended before the instant when loaded then the first camera is the hero`() async {
        // given
        let timeline = DayTimeline(markers: [alertMarker(camera: frontDoor, start: at(999_000), end: at(999_500))], motion: [], gaps: [])
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.heroCamera?.name == driveway.name)
    }

    @Test func `given an in-progress alert started before the instant when loaded then its camera is the hero`() async {
        // given — `end == nil` runs to the live edge, so it is still active exactly at it
        let timeline = DayTimeline(markers: [alertMarker(camera: frontDoor, start: at(999_000), end: nil)], motion: [], gaps: [])
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.heroCamera?.name == frontDoor.name)
    }

    @Test func `given only a detection active at the instant when loaded then the first camera is the hero`() async {
        // given — detections never take the hero
        let timeline = DayTimeline(markers: [detectionMarker(camera: frontDoor, start: at(999_990), end: nil)], motion: [], gaps: [])
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.heroCamera?.name == driveway.name)
    }

    @Test func `given an alert for a camera that is not in the list when loaded then the first camera is the hero`() async {
        // given
        let timeline = DayTimeline(
            markers: [ReviewMarker(camera: CameraName("shed"), start: at(999_990), end: nil, severity: .alert, label: "Person")],
            motion: [], gaps: []
        )
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.heroCamera?.name == driveway.name)
    }

    // `scrub(to:)` moves the clock, then a `followHero` tick applies the new hero — the view model
    // no longer recomputes per scroll offset, so the test drives both steps itself.
    @Test func `given an alert active at the instant when scrubbing past its end then the hero returns to the first camera`() async {
        // given — scrub into the alert's window before loading, so the hero starts as front_door
        let timeline = DayTimeline(markers: [alertMarker(camera: frontDoor, start: at(999_000), end: at(999_500))], motion: [], gaps: [])
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)
        scenario.sut.scrub(to: at(999_200))
        await scenario.sut.load()
        #expect(scenario.sut.heroCamera?.name == frontDoor.name)

        // when — the clock moves past the alert's end, and a follow tick applies it
        scenario.sut.scrub(to: at(999_600))
        let task = Task { await scenario.sut.followHero(every: .milliseconds(1)) }
        await settle { scenario.sut.heroCamera?.name == driveway.name }
        task.cancel()

        // then
        #expect(scenario.sut.heroCamera?.name == driveway.name)
    }

    @Test func `given no cameras when loaded then there is no hero`() async {
        // given
        let scenario = Scenario(cameras: [], timeline: emptyTimeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.heroCamera == nil)
    }
}

@MainActor
struct TimelineHeroOrderedCamerasTests {

    @Test func `given a hero when ordering the grid then the hero is first and the rest keep their order`() async {
        // given
        let timeline = DayTimeline(markers: [alertMarker(camera: backyard, start: at(999_990), end: nil)], motion: [], gaps: [])
        let scenario = Scenario(cameras: [driveway, frontDoor, backyard], timeline: timeline, now: now)
        await scenario.sut.load()
        #expect(scenario.sut.heroCamera?.name == backyard.name)

        // when
        let ordered = scenario.sut.heroOrderedCameras([driveway, frontDoor, backyard])

        // then
        #expect(ordered.map(\.name) == [backyard.name, driveway.name, frontDoor.name])
    }

    @Test func `given no hero when ordering the grid then the order is unchanged`() async {
        // given — no `load()`, so `heroCamera` stays at its nil default
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: emptyTimeline, now: now)

        // when
        let ordered = scenario.sut.heroOrderedCameras([driveway, frontDoor])

        // then
        #expect(ordered.map(\.name) == [driveway.name, frontDoor.name])
    }
}

@MainActor
struct TimelineAlertLabelsTests {

    @Test func `given an alert with an object label when loaded then the camera's badge label is that object`() async {
        // given
        let timeline = DayTimeline(markers: [alertMarker(camera: frontDoor, start: at(999_990), end: nil, label: "Car")], motion: [], gaps: [])
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.alertLabels[frontDoor.name] == "Car")
    }

    @Test func `given two cameras with alerts when loaded then each camera keeps its own badge label`() async {
        // given
        let timeline = DayTimeline(
            markers: [
                alertMarker(camera: driveway, start: at(999_990), end: nil, label: "Car"),
                alertMarker(camera: frontDoor, start: at(999_980), end: nil, label: "Person"),
            ],
            motion: [], gaps: []
        )
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.alertLabels[driveway.name] == "Car")
        #expect(scenario.sut.alertLabels[frontDoor.name] == "Person")
    }

    @Test func `given only a detection active at the instant when loaded then no camera has a badge label`() async {
        // given
        let timeline = DayTimeline(markers: [detectionMarker(camera: frontDoor, start: at(999_990), end: nil)], motion: [], gaps: [])
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)

        // when
        await scenario.sut.load()

        // then
        #expect(scenario.sut.alertLabels.isEmpty)
    }

    @Test func `given an alert that ended before the instant when scrubbing into it then the camera gains a badge label`() async {
        // given — the alert has already ended relative to the live edge, so no badge at load
        let timeline = DayTimeline(
            markers: [alertMarker(camera: frontDoor, start: at(999_000), end: at(999_500), label: "Person")],
            motion: [], gaps: []
        )
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)
        await scenario.sut.load()
        #expect(scenario.sut.alertLabels[frontDoor.name] == nil)

        // when — scrub into the alert's window and let the loop recompute (not `scrub(to:)` itself)
        scenario.sut.scrub(to: at(999_200))
        let task = Task { await scenario.sut.followHero(every: .milliseconds(1)) }
        await settle { scenario.sut.alertLabels[frontDoor.name] != nil }
        task.cancel()

        // then
        #expect(scenario.sut.alertLabels[frontDoor.name] == "Person")
    }
}

@MainActor
struct TimelineFollowHeroTests {

    @Test func `given the hero's alert ends while the follow loop runs then the hero returns to the first camera`() async {
        // given — scrubbed into the alert's window before loading, so the hero starts as front_door
        let timeline = DayTimeline(markers: [alertMarker(camera: frontDoor, start: at(999_000), end: at(999_500))], motion: [], gaps: [])
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: timeline, now: now)
        scenario.sut.scrub(to: at(999_200))
        await scenario.sut.load()
        #expect(scenario.sut.heroCamera?.name == frontDoor.name)

        // when — the loop is already running when the clock advances past the alert's end
        let task = Task { await scenario.sut.followHero(every: .milliseconds(1)) }
        scenario.sut.scrub(to: at(999_600))
        await settle { scenario.sut.heroCamera?.name == driveway.name }
        task.cancel()
        await task.value

        // then — the hero reverted, and the loop actually stopped
        #expect(scenario.sut.heroCamera?.name == driveway.name)
        #expect(task.isCancelled)
    }

    // The guard that keeps `@Observable` from invalidating the grid every second is the whole
    // point of the loop, so it gets its own test: a change-counter must stay at zero across
    // several ticks that recompute to the identical hero/labels.
    @Test func `given an unchanged hero when the loop ticks then the published values are not rewritten`() async {
        // given — no alerts, so every tick recomputes the same fallback hero and empty labels
        let scenario = Scenario(cameras: [driveway, frontDoor], timeline: emptyTimeline, now: now)
        await scenario.sut.load()
        #expect(scenario.sut.heroCamera?.name == driveway.name)

        // `withObservationTracking`'s `onChange` is `nonisolated`, so a plain captured `var` would
        // race under strict concurrency; the test only ever reads it back on the main actor after
        // the loop is cancelled, so the lack of synchronization is safe in practice.
        nonisolated(unsafe) var changeCount = 0
        withObservationTracking {
            _ = scenario.sut.heroCamera
            _ = scenario.sut.alertLabels
        } onChange: {
            changeCount += 1
        }

        // when
        let task = Task { await scenario.sut.followHero(every: .milliseconds(1)) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // then
        #expect(changeCount == 0)
    }
}

// MARK: - Helpers

private let now = at(1_000_000)
private let emptyTimeline = DayTimeline(markers: [], motion: [], gaps: [])

private let driveway = Camera(name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: ["driveway"])
private let frontDoor = Camera(name: CameraName("front_door"), friendlyName: "Front Door", isEnabled: true, streamNames: ["front_door"])
private let backyard = Camera(name: CameraName("backyard"), friendlyName: "Backyard", isEnabled: true, streamNames: ["backyard"])

private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

private func alertMarker(camera: Camera, start: Date, end: Date?, label: String = "Person") -> ReviewMarker {
    ReviewMarker(camera: camera.name, start: start, end: end, severity: .alert, label: label)
}

private func detectionMarker(camera: Camera, start: Date, end: Date?, label: String = "Motion") -> ReviewMarker {
    ReviewMarker(camera: camera.name, start: start, end: end, severity: .detection, label: label)
}

/// Spins on a short real sleep until `condition` holds or `timeout` elapses — the follow loop
/// ticks on a real `Task.sleep`, so a bare `Task.yield()` spin (as elsewhere in this file) cannot
/// be relied on to let wall-clock time actually pass.
@MainActor
private func settle(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

@MainActor
private struct Scenario {
    let sut: TimelineScreenViewModel

    init(cameras: [Camera], timeline: DayTimeline, now: Date) {
        sut = TimelineScreenViewModel(
            observeCameras: ObserveCameras(
                getCameras: GetCameras(repository: FakeCamerasRepository(.success(cameras))),
                observeCameraOrder: ObserveCameraOrder(repository: FakeSettingsRepository())
            ),
            getDayTimeline: GetDayTimeline(repository: FakeCameraDayTimelineRepository(.success(timeline))),
            now: { now },
            days: 7
        )
    }
}
