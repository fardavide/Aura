# Aura

A native **iOS + macOS** SwiftUI client for [Frigate NVR](https://frigate.video) — a personal,
single-user companion app and portfolio piece.

## Features

- **Cameras** — live grid of all cameras, with a user-defined order; tap a tile for fullscreen
  live playback (go2rtc HLS via AVFoundation) with Picture-in-Picture on iOS and pinch-to-zoom + pan.
- **Timeline** — a synced multi-camera scrub view: preview tiles over a single continuous
  scrollable timeline with an activity histogram (Liquid Glass), Hour/Day/Week zoom, and a
  30-second live-edge auto-refresh. iPhone landscape gets a dedicated side-by-side layout.
- **Events** — detection event list (thumbnail, label, camera, time) with recorded-clip playback.
- **Settings** — Frigate server connection (password in Keychain), theme, and camera ordering.

## Requirements

- iOS 26 / macOS 26, Xcode 26.
- A reachable [Frigate](https://frigate.video) 0.17 server.

## Tech

Swift 6 (strict concurrency), SwiftUI + `@Observable`, AVFoundation/AVKit, `URLSession` + `Codable`.
Feature-vertical Clean Architecture in a local `AuraKit` package. **Zero runtime dependencies**
(the only package dependency, `swift-snapshot-testing`, is test-only). See
[.ai/docs](.ai/docs/README.md) for architecture and decisions.

## Build & test

```bash
cd AuraKit && swift test                                                        # package logic tests
xcodebuild build -scheme Aura -destination 'generic/platform=iOS Simulator' -quiet
xcodebuild test  -scheme Aura -destination 'platform=iOS Simulator,name=iPhone 17 Pro'  # app + screenshot tests
```

The screenshot tests render every screen across the full device matrix (iPhone/iPad ×
portrait/landscape × light/dark) in code, so a single simulator run covers all of them.

CI builds both platforms and runs the tests on every push/PR to `main`.

## Changelog

### 0.3.1 — 2026-07-15
- Cameras: finished the grid redesign. A summary card up top shows what's happening **right now**
  (tap it to jump to that camera), **today's** event count with a breakdown, and **recording**
  disk space + how many days are kept. When your Frigate config defines camera groups, filter
  chips let you narrow the grid to one group. Tiles now refresh every 2 seconds.

### 0.3.0 — 2026-07-15
- Cameras: redesigned grid. Richer live tiles with a LIVE marker, an offline treatment, and
  activity badges (person / vehicle) when Frigate is tracking something; a live·offline count in
  the header; and an adaptive layout — a full-width list in portrait, a grid in landscape / on
  iPad / on Mac. Tiles refresh every few seconds while the grid is open.

### 0.2.5 — 2026-07-14
- Settings (macOS): the settings forms and the drilled-in camera-reorder sheet now lay out
  correctly on Mac.

### 0.2.4 — 2026-07-14
- Live (iOS): pinch-to-zoom no longer competes with the player's own built-in zoom, so it's
  easier to trigger and pans correctly.

### 0.2.3 — 2026-07-13
- Live: pinch-to-zoom now zooms about the pinch point rather than the center of the frame.

### 0.2.2 — 2026-07-13
- Timeline: live-hour camera tiles now show the current footage instead of freezing on the last
  frame of the previous hour — the in-progress hour has no preview clip yet, so tiles fall back to
  the nearest preview frame.

### 0.2.1 — 2026-07-13
- Live: the camera stream now recovers automatically after an audio-session interruption.

### 0.2.0 — 2026-07-06
- Camera ordering: drag-to-reorder editor in Settings; the camera grid and timeline follow the
  order live.
- Settings reorganized: server connection moves to its own sub-screen; theme applies on change.
- Snapshot tests for the Cameras grid, Events list, and Settings screens; test doubles
  consolidated into a shared target.

### 0.1.10 — 2026-07-02
- Pinch-to-zoom + pan (1x–4x) on the live camera view, on both platforms.

### 0.1.9 — 2026-06-30
- iPhone-landscape timeline layout: camera tiles on the left, a full-height vertical scrubber on
  the right (up = back in time).

### 0.1.8 — 2026-06-29
- Timeline auto-refreshes at the live edge every 30 seconds and self-recovers from a dropped
  connection.
- GitHub Actions CI: iOS + macOS builds and tests.

### 0.1.7 — 2026-06-29
- Scrubber polish: white bordered track, blue playhead, hatched no-footage regions.

### 0.1.6 — 2026-06-28
- Liquid-Glass histogram scrubber: motion activity bars colored by severity, date/time readout,
  Hour/Day/Week zoom.

### 0.1.5 — 2026-06-28
- Timeline becomes a single continuous scrollable track with a fixed center playhead (~7-day span).

### 0.1.4 — 2026-06-28
- Timeline tab: synced all-camera preview-scrub grid with local seeking and a shared scrub clock.

### 0.1.3 — 2026-06-28
- Events: detection list + detail with recorded-clip playback. App becomes a tab bar
  (Cameras | Events).

### 0.1.2 — 2026-06-28
- Live camera detail: fullscreen go2rtc HLS playback with Picture-in-Picture on iOS
  (verified on-device via TestFlight).

### 0.1.1 — 2026-06-28
- Settings (server connection + theme) and the live camera grid; first TestFlight build.

### 0.1.0 — 2026-06-27
- Project scaffold: `AuraKit` package, Cameras data foundation, Frigate camera list +
  authenticated image loading.
