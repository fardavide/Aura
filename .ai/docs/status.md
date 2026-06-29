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
  clock fans out to a per-tile **coalescing** controller (latest-target-wins, no debounce); at the
  live edge tiles fall back to the latest footage. 3rd tab (Cameras | Timeline | Events). The
  cross-platform video/image wrapper was extracted into a shared **`CommonPlayer`** target.
  **(v0.1.4 grid → v0.1.5 scrollable timeline → v0.1.6 Liquid-Glass histogram scrubber → v0.1.7
  track polish: white inset + border, blue playhead, hatched no-footage, bars flush to bottom.)**

Package logic is covered by Swift Testing (~104 tests). The **Timeline screen** is covered by
**screenshot tests** (app-hosted `AuraTests`, `swift-snapshot-testing`, test-only) across iPhone +
iPad (portrait + landscape) × light + dark on the simulator — ready (busy / gappy / quiet), empty,
and failed states.
Reference PNGs are committed beside the tests. macOS is excluded (AppKit offscreen rendering can't
capture glass faithfully — see `decisions.md`). Other SwiftUI views are built, not yet snapshot-tested.

## Next
- **Single-cam recordings scrubber.** Tap a Timeline tile → that camera's full-res recordings
  scrubber via the VOD HLS URL (`/vod/{camera}/start/{s}/end/{e}/master.m3u8`). **Start with an
  on-device spike**: AVPlayer scrubbing Frigate's VOD HLS is unproven (the web UI uses hls.js on
  every platform, never native). Bound playback windows to ~1h (nginx-vod segment cap).
- **Timeline follow-ups**: auto-load ranges older than the current ~7-day span as you scroll; the
  current-hour `.webp` preview-frame path (tiles use the latest-footage fallback at the live edge
  for now); the `camera=all` batch clip-list optimization; richer markers.
- A real **app icon** (current is a placeholder).
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
