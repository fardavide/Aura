# Status & roadmap

## Done
- **Slice 1 — data foundation.** `AuraKit` package; Cameras Domain/Data; Common Network/Frigate;
  Frigate camera list + authed image loader; decoding + repository tests. Wired into `Aura.xcodeproj`.
- **Slice 2 — Settings + camera grid.** Settings feature (connection config + theme; UserDefaults +
  Keychain); Cameras presentation (grid + tiles); composition root + root view. App runs: no
  connection → Settings; save → grid.
- **Slice 3 — live camera detail.** Tap a tile → fullscreen live go2rtc HLS via AVFoundation
  (`AVPlayerViewController` + PiP on iOS, `AVPlayerView` on macOS) behind a cross-platform wrapper;
  audio session at launch. Stream URL is the Frigate-proxied go2rtc path. **Live playback + PiP
  verified working on-device (v0.1.2 via TestFlight).**
- **Slice 4 — Events.** Event list (thumbnail, label, camera, time) + detail with recorded-clip
  playback (SwiftUI `VideoPlayer`, auth headers). App is now a **TabView (Cameras | Events)**,
  Settings reachable from each. **MVP feature-complete.**
- **Slice 5 — Timeline (multi-cam scrub).** New `Timeline` feature vertical: a synced all-camera
  **preview-scrub grid** (Cameras-sized tiles) over a single **continuous scrollable timeline**
  (scroll/pan = scrub; fixed center playhead; ~7-day span). The scrubber is a **Liquid-Glass card**
  (`glassEffect`) floating over the grid so tiles refract through it: an activity **histogram**
  (motion height, colored by severity), dimmed gaps, a date/time readout, and an Hour/Day/Week
  **zoom** (glass button). Past-hour low-res `preview.mp4` tiles seek **locally**; one shared scrub
  clock fans out to a per-tile **coalescing** controller (latest-target-wins, no debounce); in the
  **live hour** (no `preview.mp4` assembled yet) tiles show the nearest `.webp` **preview frame**,
  falling back to the latest clip's last frame only when no frame exists (v0.2.2 — fixes tiles
  freezing at the top of the current hour; see `decisions.md`). 3rd tab (Cameras | Timeline | Events). The
  cross-platform video/image wrapper was extracted into a shared **`CommonPlayer`** target.
  **(v0.1.4 grid → v0.1.5 scrollable timeline → v0.1.6 Liquid-Glass histogram scrubber → v0.1.7
  track polish: white inset + border, blue playhead, hatched no-footage, bars flush to bottom.)**
  A **30s live-edge auto-refresh** (v0.1.8) keeps the histogram current without an app restart: it extends the
  span end to the present (start fixed, so tiles don't reload) and only fires when parked at the live
  edge and not scrubbing; a failed screen keeps retrying so a dropped connection self-recovers
  (see `decisions.md`).
  When the vertical size class is compact — iPhone landscape in practice (iPad keeps a regular height
  even in multitasking; macOS has no size class) — the layout splits side-by-side (v0.1.9) and hides the
  nav bar: a single-column scroll of camera tiles on the left, and a **full-height vertical** glass
  scrubber on the right that's kept visually identical to the bottom card (centered playhead, same
  histogram and zoom scale) except it reads top→bottom now→past, so scrolling **up** goes back in time
  (`ScrollableTimelineView` gained an `axis`). Everything else keeps the bottom card. See `decisions.md`
  — only the iPhone-landscape snapshot baselines change and need re-recording.

- **Pinch-to-zoom on the live view (v0.1.10).** Digital zoom + pan (1x–4x) on the live camera detail, both
  platforms: pinch (touch / trackpad magnify) zooms about the pinch point, drag pans with the
  content edges clamped to the viewport, double-tap toggles 1x↔2x at the tap point. The pinch
  anchor comes from `MagnifyGesture`'s start **location** (v0.2.3) — its `startAnchor` reports
  `.center` in practice, which pinned every pinch to the middle of the frame. A SwiftUI
  gesture container in `CommonPlayer` wraps the untouched platform players (PiP and the player's
  own controls unaffected — `simultaneousGesture`); the clamped zoom/pan math is a pure value type
  unit-tested in the package. Gesture feel + PiP handback still need an on-device pass. See
  `decisions.md`.

- **Slice 6 — user-defined camera order (v0.2.0).** Drag-to-reorder editor in Settings ("Camera Order",
  `List` + `.onMove`, save-on-move, shown only once a connection exists); the order is a Settings
  preference (`[CameraName]` on the one `SettingsRepository`, UserDefaults) **observed reactively**:
  `ObserveCameras` (CamerasDomain) re-emits the sorted list on every change, so the Cameras grid and
  the Timeline re-sort live — no manual propagation. Cross-feature camera types (`CameraName`,
  `CameraStreamSource`) moved to the new pure **`CamerasEntities`** target. Sort contract: saved
  names first in saved order, new cameras appended alphabetically, stale names ignored. See
  `decisions.md`. Settings became a **menu** (Server sub-screen with its own Save, Camera Order,
  inline theme picker saving on change, Done to close). Settings became a **menu** (Server sub-screen with its own Save, Camera Order,
  inline theme picker saving on change, Done to close); shared test doubles moved to the
  **`TestDoubles`** target (product `AuraKitTestDoubles`).

Package logic is covered by Swift Testing (150 tests). All four main screens — **Timeline**
(ready busy / gappy / quiet, empty, failed), the **Cameras grid**, the **Events list**, and
**Settings** (each across its loaded/empty/failed or first-run/saved/error states) — are covered
by **screenshot tests** (app-hosted `AuraTests`, `swift-snapshot-testing`, test-only) across
iPhone + iPad (portrait + landscape) × light + dark on the simulator.
Reference PNGs are committed beside the tests. macOS is excluded (AppKit offscreen rendering can't
capture glass faithfully — see `decisions.md`). The detail screens (live camera, event clip) are
not snapshot-tested — they center on video players that can't render in a snapshot.

## Next
- **Xcode Cloud workflow (App Store Connect, manual)**: **remove the two test actions** (iOS +
  macOS), keep the archives. Verified 2026-07-07: even the package-owned `AuraKitTests` scheme
  hits the app-container limitation on Xcode Cloud — both test actions fail with "1 error,
  0 test failures" before any test runs (see `decisions.md`). All testing is carried by the
  PR gate on `main`, so archives only ever see verified commits.
- **Single-cam recordings scrubber.** Tap a Timeline tile → that camera's full-res recordings
  scrubber via the VOD HLS URL (`/vod/{camera}/start/{s}/end/{e}/master.m3u8`). **Start with an
  on-device spike**: AVPlayer scrubbing Frigate's VOD HLS is unproven (the web UI uses hls.js on
  every platform, never native). Bound playback windows to ~1h (nginx-vod segment cap).
- **Timeline follow-ups**: auto-load ranges older than the current ~7-day span as you scroll; the
  `camera=all` batch clip-list optimization; richer markers. Live-hour frames are fetched once per
  tile on appear, so leaving the screen open for a long stretch without scrubbing won't pull newer
  frames until a re-appearance or scrub (the histogram still auto-refreshes) — a continuous
  live-follow of the tiles is a further follow-up.
- A real **app icon** (current is a placeholder; the mac slots are `sips` downscales of the
  1024px source — regenerate them with the new artwork, and keep them filled: empty mac slots
  ship no macOS icon at all, see the App Store packaging decision).
- **Refactor**: extract a shared `FrigateApiClient` in `CommonFrigate` — the authed-GET +
  status→error mapping is now duplicated across the Cameras, Events, **and Timeline** repositories.
- A **stream picker** when a camera exposes multiple go2rtc sources; **PiP keep-alive** across navigation.
- Push notifications — out of MVP scope.

## Runtime config still needed (before the grid loads a real server)
Code is done; these are OS-policy settings, not code:
- **iOS** — App Transport Security blocks cleartext HTTP; a LAN/Tailscale `http://` server needs an
  ATS exception (custom `Info.plist`) and possibly Local Network permission.
- **macOS** — the app sandbox needs `com.apple.security.network.client` + a keychain entitlement.

## Build & run
- Package tests: `cd AuraKit && swift test` (fast, runs on the macOS host).
- App: `xcodebuild build -scheme Aura -destination 'generic/platform=iOS Simulator'` (and `…/macOS`).
- Build **one platform at a time with `-jobs` capped** — back-to-back parallel `xcodebuild` runs
  once exhausted the macOS per-user process limit (`fork: resource temporarily unavailable`).
- **CI:** `.github/workflows/ci.yml` runs on `macos-26` for every push/PR to `main` — unit tests
  (`swift test`), iOS + macOS app builds, and an isolated gating snapshot job. See `decisions.md`.
