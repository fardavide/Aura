import Foundation
import SwiftUI

import SnapshotTesting

import CamerasDomain
import CamerasEntities
import CommonDesign
import SettingsDomain
import TestDoubles
import TimelineDomain
import TimelinePresentation

// Scaffolding shared by the screenshot tests (Timeline, Cameras, Events, Settings). These live
// in the app-hosted `AuraTests` target (not the AuraKit package) on purpose: only an app-hosted
// target gives the tests a real host window, so the full `NavigationStack` screen lays out and
// Liquid Glass renders via `drawHierarchyInKeyWindow`. The package test targets are hostless and
// render the screen blank without glass. See `.ai/docs/decisions.md`.
//
// Inputs are fixed (instant, calendar, time zone, color scheme) so the same pixels render on any
// machine. Reference images live in `__Snapshots__/` beside the test file. To (re)generate them,
// run the suite once — missing references are written and the run fails; commit them, then a
// second run compares. Each logical view is captured across the device + orientation matrix on
// iOS and a fixed window on macOS.

// MARK: - Fixed inputs

/// The instant every snapshot is taken at — a fixed epoch so the clock and labels never drift.
let snapshotNow = Date(timeIntervalSince1970: 1_000_000)
let snapshotDays = 2

func snapshotCameras() -> [Camera] {
    [
        Camera(name: CameraName("driveway"), friendlyName: "Driveway", isEnabled: true, streamNames: ["driveway"]),
        Camera(name: CameraName("front_door"), friendlyName: "Front Door", isEnabled: true, streamNames: ["front_door"]),
        Camera(name: CameraName("backyard"), friendlyName: "Backyard", isEnabled: true, streamNames: ["backyard"]),
        Camera(name: CameraName("garage"), friendlyName: "Garage", isEnabled: true, streamNames: ["garage"]),
    ]
}

/// In-progress activity for two of the `snapshotCameras()` — an alert and a detection — to exercise
/// the tile badges.
func snapshotActivity() -> [CameraActivity] {
    [
        CameraActivity(camera: CameraName("front_door"), label: "Person", severity: .alert, startedAt: snapshotNow),
        CameraActivity(camera: CameraName("driveway"), label: "Car", severity: .detection, startedAt: snapshotNow),
    ]
}

let snapshotSpanStart = Date(timeIntervalSince1970: 1_000_000 - Double(2 * 86_400))

/// A busy day: a swelling motion profile with night lulls, alert/detection markers (one still
/// in progress), and a footage gap.
func richTimelineFixture() -> DayTimeline {
    func at(hour: Double) -> Date { snapshotSpanStart.addingTimeInterval(hour * 3600) }

    let motion: [MotionBucket] = stride(from: 0.0, to: 48.0, by: 0.5).map { hour in
        let swell = sin(hour / 2.0) * 35 + 45
        let burst = hour.truncatingRemainder(dividingBy: 6) < 0.5 ? 40.0 : 0
        let lull = (hour > 2 && hour < 6) || (hour > 26 && hour < 30) ? 0.0 : 1.0
        let value = max(0, min(100, (swell + burst) * lull))
        return MotionBucket(time: at(hour: hour), intensity: Int(value))
    }
    let markers: [ReviewMarker] = [
        ReviewMarker(camera: CameraName("front_door"), start: at(hour: 9), end: at(hour: 9.6), severity: .alert, label: "Person"),
        ReviewMarker(camera: CameraName("driveway"), start: at(hour: 15.5), end: at(hour: 16.2), severity: .detection, label: "Car"),
        ReviewMarker(camera: CameraName("backyard"), start: at(hour: 33), end: at(hour: 34), severity: .alert, label: "Person"),
        ReviewMarker(camera: CameraName("garage"), start: at(hour: 46.5), end: nil, severity: .detection, label: "Motion"),
    ]
    let gaps = [FootageGap(range: TimeRange(start: at(hour: 19), end: at(hour: 21)))]
    return DayTimeline(markers: markers, motion: motion, gaps: gaps)
}

/// An alerting camera: an **in-progress** alert (`end: nil`) on `front_door`, started before
/// `snapshotNow`, plus a completed detection on `driveway`. Drives the hero to `front_door`
/// (≠ the first camera) so `ready-hero-alert` exercises the hero swap and its badge.
func heroAlertTimelineFixture() -> DayTimeline {
    let markers: [ReviewMarker] = [
        ReviewMarker(
            camera: CameraName("front_door"), start: snapshotNow.addingTimeInterval(-600), end: nil,
            severity: .alert, label: "Person"
        ),
        ReviewMarker(
            camera: CameraName("driveway"),
            start: snapshotNow.addingTimeInterval(-3_600), end: snapshotNow.addingTimeInterval(-3_300),
            severity: .detection, label: "Car"
        ),
    ]
    return DayTimeline(markers: markers, motion: [], gaps: [])
}

/// A base64 1×1 **opaque** PNG (no alpha) — `.resizable().scaledToFill()` fills the tile with one
/// flat colour, so a footage-bearing baseline is stable across machines.
let solidPreviewPng = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAAD0lEQVR4AQEEAPv/AICAgAMEAYGkH5BXAAAAAElFTkSuQmCC"
)!

/// Footage but no detected activity — exercises the empty histogram with cameras present.
func quietTimelineFixture() -> DayTimeline {
    DayTimeline(markers: [], motion: [], gaps: [])
}

/// Sparse motion broken up by several large no-footage gaps (hatched).
func gappyTimelineFixture() -> DayTimeline {
    func at(hour: Double) -> Date { snapshotSpanStart.addingTimeInterval(hour * 3600) }

    let motion: [MotionBucket] = stride(from: 0.0, to: 48.0, by: 1.0).map { hour in
        MotionBucket(time: at(hour: hour), intensity: Int(hour) % 7 == 0 ? 70 : 15)
    }
    let gaps = [
        FootageGap(range: TimeRange(start: at(hour: 3), end: at(hour: 8))),
        FootageGap(range: TimeRange(start: at(hour: 13), end: at(hour: 14.5))),
        FootageGap(range: TimeRange(start: at(hour: 28), end: at(hour: 36))),
    ]
    return DayTimeline(markers: [], motion: motion, gaps: gaps)
}

// MARK: - View builder

/// The full timeline screen, driven to a terminal state. Camera tiles are pre-settled to the
/// `.unavailable` placeholder (no live video, no animated spinner) so the grid is stable.
@MainActor
func timelineScreen(
    cameras: Result<[Camera], CamerasError>,
    timeline: Result<DayTimeline, TimelineError>,
    playing: Bool = false,
    // Defaults (no clips, no frames, no image) drive every tile to `.unavailable` — today's
    // behaviour, unchanged for every existing call site. `ready-hero-alert` hands in real
    // material; `ready-tile-failed` hands in a provider whose `clipsResult` is a failure.
    previews: FakeCameraPreviewProvider = FakeCameraPreviewProvider(),
    imageLoader: FakePreviewImageLoader = FakePreviewImageLoader()
) async -> some View {
    let viewModel = TimelineScreenViewModel(
        observeCameras: ObserveCameras(
            getCameras: GetCameras(repository: FakeCamerasRepository(cameras)),
            observeCameraOrder: ObserveCameraOrder(repository: FakeSettingsRepository())
        ),
        getDayTimeline: GetDayTimeline(repository: FakeCameraDayTimelineRepository(timeline)),
        now: { snapshotNow },
        days: snapshotDays
    )
    await viewModel.load()
    if playing {
        viewModel.transport.select(.fourX)
        viewModel.transport.togglePlayPause()
    }

    let previews = GetCameraPreviews(provider: previews)
    let recordings = GetCameraRecordings(repository: FakeCameraRecordingsRepository(.success([])))
    var tiles: [CameraName: PreviewTileViewModel] = [:]
    if case let .success(all) = cameras {
        for camera in all where camera.isEnabled {
            let tile = PreviewTileViewModel(
                camera: camera,
                previews: previews,
                recordings: recordings,
                imageLoader: imageLoader
            )
            await tile.prepare(range: viewModel.span, at: viewModel.clock.instant)
            tiles[camera.name] = tile
        }
    }
    // The frame path's image decode finishes in a detached `@MainActor` task (itself hopping off
    // and back on to await the image loader), so `prepare(...)` alone can leave a tile on
    // `.loading` a few run-loop turns longer — a helper-local wait, no production change.
    for _ in 0..<5 { await Task.yield() }

    return TimelineScreenView(
        viewModel: viewModel,
        makeTileViewModel: {
            tiles[$0.name] ?? PreviewTileViewModel(
                camera: $0,
                previews: previews,
                recordings: recordings,
                imageLoader: imageLoader
            )
        },
        // Never invoked in a snapshot — the destination is only built once a tile is tapped.
        makeRecordingPlayerViewModel: { camera, instant in
            RecordingPlayerViewModel(
                camera: camera,
                recordings: GetCameraRecordings(repository: FakeCameraRecordingsRepository(.success([]))),
                getDayTimeline: GetDayTimeline(
                    repository: FakeCameraDayTimelineRepository(.success(quietTimelineFixture()))
                ),
                filmstrip: RecordingFilmstripStore(
                    camera: camera.name,
                    previews: GetCameraPreviews(provider: FakeCameraPreviewProvider()),
                    imageLoader: FakePreviewImageLoader()
                ),
                now: { snapshotNow },
                startingAt: instant,
                days: snapshotDays
            )
        }
    )
}

// MARK: - Rendering

extension View {
    /// Pins the locale, calendar, and time zone so date/time rendering is identical on every machine
    /// the snapshots run on. The color scheme is applied per-snapshot (both light and dark).
    func snapshotEnvironment() -> some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return self
            .environment(\.locale, Locale(identifier: "en_US_POSIX"))
            .environment(\.calendar, calendar)
            .environment(\.timeZone, .gmt)
            // Freezes the live-pill blink and the segmented-control slide on their first frame —
            // without it, an idle animation can be mid-transition at capture time.
            .environment(\.designMotion, .still)
    }
}

// Liquid Glass is not deterministic. Re-rendering the same screen re-draws the whole glass panel a
// shade differently — measured at ~26% of an iPad frame drifting by 1–15/255, while the text and
// shapes *on* the glass stay pixel-stable. `warmUpRender` reduces it but cannot remove it.
//
// So the two knobs do different jobs, and only one of them may be spent on that drift:
//   - `perceptualPrecision` sets the **per-pixel** ΔE threshold below which a difference is free
//     ((1 - value) × 100). It has to clear the glass drift, and it has to clear it on a GPU-less CI
//     runner, whose ΔE scoring reads higher than a local one's — CI measured a worst pixel at ~10.1
//     where 0.95 allowed only 5, which is what turned PR #30 red.
//   - `precision` is the **area** budget: the fraction of pixels allowed to exceed that threshold.
//     It gates whatever repaints a large share of a frame — a relaid-out screen, a wrong background,
//     a control that moved. It does **not** gate small chrome: 2% of an iPhone frame is ~59k pixels,
//     and 0.5.4 walked straight through it. That change flipped the scrubber's default zoom, which
//     relabels the pill (Day → Hour, and the pill resizes with the word) and redraws the histogram
//     bars at 4× density — yet all four Timeline states passed against references that still show
//     "Day", because the repainted area is ~1% of the frame.
// So read a green run as "nothing moved across a large area", not as "the screen is unchanged", and
// re-record baselines whenever a change alters what a screen depicts even if the suite stayed green
// — a stale reference silently becomes the thing every later diff is measured against.
// See `decisions.md`.
private let snapshotPrecision: Float = 0.98
private let snapshotPerceptualPrecision: Float = 0.87

#if os(iOS)
import UIKit

private struct SnapshotConfig {
    let name: String
    let device: ViewImageConfig
}

/// Renders `view` once in a real key window (at the snapshot's size + style) to warm up the Liquid
/// Glass shader and glyph caches before capture — a cold first render in a fresh process can differ
/// slightly from later ones, which would otherwise show up as a flaky diff.
@MainActor
private func warmUpRender(_ view: some View, size: CGSize, style: UIUserInterfaceStyle) {
    let host = UIHostingController(rootView: view)
    host.overrideUserInterfaceStyle = style
    host.view.frame = CGRect(origin: .zero, size: size)
    let window = UIWindow(frame: host.view.frame)
    window.overrideUserInterfaceStyle = style
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    window.isHidden = true
    window.rootViewController = nil
}

/// Redirects swift-snapshot-testing's failure artifacts — the freshly-rendered image it writes on a
/// mismatch — into a predictable `__SnapshotFailures__/` folder beside the `__Snapshots__/` baselines,
/// unless the caller already pinned `SNAPSHOT_ARTIFACTS`. By default those images land in a per-run
/// temp directory inside the simulator's data container, effectively unreachable. Pinned here, a
/// failing run (local or CI) leaves a tidy tree mirroring the baselines — exactly the screens that
/// didn't match, same relative path — ready to diff by eye against `__Snapshots__/`. On CI the diff
/// report is built straight from this folder (see `.github/scripts/snapshot-report.py`). Idempotent:
/// only the first snapshot in the process sets the variable.
private func redirectSnapshotFailureArtifacts(besideBaselinesOf filePath: StaticString) {
    guard ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"] == nil else { return }
    let testDirectory = URL(fileURLWithPath: "\(filePath)").deletingLastPathComponent()
    let failuresDirectory = testDirectory.appendingPathComponent("__SnapshotFailures__")
    setenv("SNAPSHOT_ARTIFACTS", failuresDirectory.path, 1)
}
#endif

/// Renders `view` across the platform's snapshot matrix and compares each against its reference.
@MainActor
func assertScreenSnapshot(
    _ view: some View,
    named name: String,
    fileID: StaticString = #fileID,
    file filePath: StaticString = #filePath,
    testName: String = #function,
    line: UInt = #line,
    column: UInt = #column
) {
    // iOS-only: macOS AppKit offscreen rendering (cacheDisplay) can't faithfully capture Liquid
    // Glass, materials, or ContentUnavailableView — it renders light-mode/blank. See decisions.md.
    #if os(iOS)
    redirectSnapshotFailureArtifacts(besideBaselinesOf: filePath)
    let base = view.snapshotEnvironment()
    let configs: [SnapshotConfig] = [
        SnapshotConfig(name: "iPhone-portrait", device: .iPhone13),
        // Landscape zeroes the safe area: the stock `iPhone13(.landscape)` config applies a
        // portrait-style notch/indicator inset that crushes the usable height to a sliver (and the
        // vertical scrubber with it), so the snapshot stops matching the real on-device height.
        SnapshotConfig(name: "iPhone-landscape", device: {
            var c = ViewImageConfig.iPhone13(.landscape)
            c.safeArea = .zero
            return c
        }()),
        SnapshotConfig(name: "iPad-portrait", device: .iPadPro11(.portrait)),
        SnapshotConfig(name: "iPad-landscape", device: .iPadPro11(.landscape)),
    ]
    let schemes: [(name: String, scheme: ColorScheme, style: UIUserInterfaceStyle)] = [
        ("light", .light, .light),
        ("dark", .dark, .dark),
    ]
    for scheme in schemes {
        let scene = base.environment(\.colorScheme, scheme.scheme)
        let traits = UITraitCollection(userInterfaceStyle: scheme.style)
        for config in configs {
            // Warm up the render (glass shader / glyph caches) at this size so the capture is stable.
            warmUpRender(scene, size: config.device.size ?? CGSize(width: 400, height: 800), style: scheme.style)
            assertSnapshot(
                of: scene,
                as: .image(
                    drawHierarchyInKeyWindow: true,
                    precision: snapshotPrecision,
                    perceptualPrecision: snapshotPerceptualPrecision,
                    layout: .device(config: config.device),
                    traits: traits
                ),
                named: "\(name).\(config.name).\(scheme.name)",
                fileID: fileID, file: filePath, testName: testName, line: line, column: column
            )
        }
    }
    #endif
}
