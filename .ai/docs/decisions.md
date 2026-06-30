# Decisions

Key choices and why (ADR-style, newest last). Several were settled with the user during design —
**check here before re-litigating.**

## Multiplatform (iOS + macOS), not iOS-only
The scaffold is a Multiplatform target and the user wants the native macOS build kept. Don't
re-narrow `SUPPORTED_PLATFORMS`. iOS-only APIs go behind a platform wrapper.

## One local package, feature-vertical, lean targets
`AuraKit` holds many small targets organised `<Feature>/<Layer>` + `Common/*`. Chosen over a
single app target (boundaries by discipline only) and over per-feature micro-packages (more
ceremony). Feature-vertical so the app scales as features grow rather than one giant Domain.

## Strict dependency rule — Frigate is an implementation detail
No Domain may depend on Frigate/networking; enforced by SwiftPM target dependencies, not
discipline. The concrete repo is named for its source (`FrigateCamerasRepository`).

## DI: constructor injection + composition root (no service locator)
Collaborators are passed via initializers; a hand-written composition root wires them. A
`Provider`/registry was considered (the user's other apps use one) but rejected for the core app
to keep dependencies explicit and compiler-checked. Tests bypass the root entirely.

## Errors: Swift 6 typed throws
Repository/use-case boundaries use `async throws(<Feature>Error)` — idiomatic, and the error type
is part of the signature. Each feature owns its domain error; the Data layer maps
transport/decoding failures into it (no HTTP/Frigate vocabulary in the Domain).

## Testing: Swift Testing, given/when/then, handwritten fakes
`@Test` with `given … when … then …` backtick names mirroring the body markers. Handwritten fakes
over mocking frameworks; test data via small local helpers.

## Naming: no consecutive uppercase
Our identifiers use single-capital segments (`Dto`, `Url`, `Http`, `Id`). Apple's own types
(`URL`, `URLSession`, `HTTPURLResponse`, `JSONDecoder`) keep their spelling.

## Settings & connection config
Minimal Settings (connection + theme). Non-secret config → `UserDefaults`, password → Keychain.
The Domain has a pure `ConnectionSettings`; the composition root maps it to the infra
`ServerConfig` (slight duplication accepted to keep the Domain infra-free).

## Authed grid images via a Domain protocol
Grid tiles load `latest.jpg` with auth. The loader is a Domain protocol implemented in Data, so
Presentation never imports Frigate infra and the auth header still reaches images.

## Agent config layout
Behavioral rules → `.claude/skills` (flat, plain names). Commands → `.claude/commands`. Narrative
findings/decisions/status → `.ai/docs/` (tool-agnostic). No `.ai` symlink scheme for skills.

## Live stream via the Frigate-proxied go2rtc path
The live view plays go2rtc HLS through Frigate's `…/api/go2rtc/api/stream.m3u8?src=` route, reusing
the configured base URL + auth (no separate go2rtc port to expose over Tailscale). It's an
undocumented proxy route (verified in 0.16/0.17); the alternative is exposing go2rtc :1984 directly.
The URL builder is isolated in `CommonFrigate` so switching is a one-liner. The player sits behind a
cross-platform wrapper (AVPlayerViewController iOS / AVPlayerView macOS); auth reaches the
`AVURLAsset` via `AVURLAssetHTTPHeaderFieldsKey`. First stream name is used; a picker comes later.

## Events: navigation + camera reuse
The app is a **TabView** (Cameras | Events); Settings opens from a gear in each tab. `EventsDomain`
reuses `CameraName` from `CamerasDomain` (a pure domain→domain dependency) rather than a raw String
or a duplicated type — keeps strong typing without introducing a shared kernel. Event clips play via
SwiftUI's built-in `VideoPlayer` (no PiP needed for a recorded clip), so Events doesn't depend on the
live-player wrapper. Known duplication to revisit: the authed-GET + status→error mapping now repeats
across the Cameras and Events repositories — extract a `FrigateApiClient` (rule of three).

## CommonPlayer: shared cross-platform video/image wrapper
The cross-platform player wrapper (`AVPlayerViewController` iOS / `AVPlayerView` macOS) + the
`platformImage(Data)->Image` helper moved out of `CamerasPresentation` into a shared `CommonPlayer`
target when the Timeline tiles needed the same bridge. Chosen over duplicating the `#if os` player
(a third `PlatformImage` copy was about to appear). `CommonPlayer` holds `VideoPlayerView` (live,
autoplay + PiP), `ScrubbingPlayerView` (externally-owned player, no PiP/controls, for scrub tiles),
`makeAuthedPlayer`, and `platformImage`. It's infra-free — `VideoPlayerView` takes `url + headers`,
not a domain type. Cameras/Events/Timeline presentation all depend on it.

## Timeline: synced multi-cam preview-scrub grid (v0.1.4)
A new `Timeline` feature vertical mirroring Frigate's Review "Motion" view. **One shared scrub clock**
(`ScrubClock`, a `Date`) is written by the day-timeline drag and read by every tile. Tiles seek
**locally** through a low-res `preview.mp4` (Frigate's preview system; `+faststart` so AVPlayer
range-seeks) — zero network per scrub once buffered. The rate-limit is a per-tile **in-flight
coalescing guard** (`PreviewTileController` behind a `PreviewScrubber` seam so the latest-wins logic
is unit-tested without AVFoundation), **not** a debounce timer — matching Frigate's client. Day
overlays (review markers, motion strip, gaps) come from `/api/review`, `/api/review/activity/motion`,
`/api/recordings/unavailable`, fetched concurrently. Endpoints + scrub rules are mapped in the
`frigate-rest` skill. **Deferred to 0.1.5**: tap → single-cam full-res VOD HLS scrubber (needs an
on-device AVPlayer-vs-hls.js spike first; bound windows to ~1h for the nginx-vod segment cap). The
current-hour `.webp` frame path is a follow-up (tiles show a placeholder for the live hour for now).

### Live-edge auto-refresh, not pull-to-refresh
The span was fixed at screen init, so new footage never appeared without an app restart. A periodic
**quiet refresh** (every 30s, owned by the view's `.task`) re-fetches the day overlays against a span
whose **end is extended to the present** while the **start stays fixed** — so the histogram grows at
the live edge and tiles (keyed on `span.start`) don't reload/flash. The `now` source is injected as a
closure (`@MainActor () -> Date`) so the span advance is deterministic in tests and snapshots. A tick
only fires when it won't disturb the user (`shouldRefreshNow`): never mid-scrub, and over loaded
content **only when parked at the live edge** (within a generous window) — historical footage doesn't
change, so refreshing it is moot and would risk yanking a user inspecting the past. Over a failed
screen it keeps retrying, so a dropped connection self-recovers. `ScrubClock.isScrubbing` — previously
only set in tests — is now driven by the histogram's `onScrollPhaseChange`, making the mid-scrub guard
real. Chose this over `.refreshable` (used by Cameras/Events) because the timeline is a scrub surface,
not a list, and "track live" wants no gesture.

## Screenshot tests: app-hosted, `swift-snapshot-testing` (test-only)
SwiftUI screenshot tests for the Timeline screen live in the **app-hosted `AuraTests` target**, not
the `AuraKit` package. Reason (verified, not assumed): only an app-hosted target gives the tests a
real host window, so the full screen lays out and the Liquid-Glass scrubber renders via the key
window. The hostless package test targets render the screen **blank** and never show glass, and they
don't even run on the simulator (they're macOS-host-only via `swift test`). Trade-offs accepted:
(1) a deliberate exception to "all tests in the SPM package" — the UI snapshot tests sit in the app
project; (2) `swift-snapshot-testing` is the **one** external dependency, added to the Xcode project's
`AuraTests` target only (not `Package.swift`), and is **test-only** — it never links into the app, so
shipped code stays dependency-free. Determinism is pinned: a fixed instant, GMT calendar/time zone,
and POSIX locale; every screen is captured in **both light and dark** (theme is a first-class app
feature), with a small perceptual tolerance because glass material is not pixel-identical across
OS/Xcode versions. Two production tweaks were made to support this and are
genuine improvements: the histogram reads the calendar from the SwiftUI environment (was a hidden
`Calendar.current` global), and the screen view-model's self-load is now idempotent so a re-appearance
keeps loaded content instead of flashing the spinner (which also lets the snapshot capture the settled
state). The matrix is **iPhone + iPad (portrait + landscape) × light + dark on the simulator**; reference PNGs
are committed beside the tests. **macOS is intentionally excluded** (verified, not assumed): the macOS
snapshot strategy renders via AppKit's offscreen `cacheDisplay`, which can't capture Liquid Glass,
materials, or `ContentUnavailableView` and ignores the forced dark appearance — it produces
light-mode/blank images, so a faithful macOS baseline isn't achievable here. (It would also have needed
the app sandbox disabled for the test host to write references.) Don't retry macOS snapshots without a
fundamentally different renderer. Known iOS limit: camera tiles can't show live video in a snapshot, so
they render the `unavailable` placeholder.

## CI: GitHub Actions, jobs split by determinism
CI runs on **GitHub-hosted `macos-26`** (Apple Silicon; ships the Xcode 26.x line). Each job selects
the newest installed Xcode 26 explicitly (`xcode-select` on the highest-versioned `Xcode_26*.app`) —
the image's default Xcode drifts release-to-release, and the macOS deployment target needs a 26.5+ SDK.
The workflow is **four jobs split by how deterministic each check is**, so a fragile check can't mask a
solid one and the failing signal is precise:
- **Unit tests** — the package suite via `swift test` on the macOS host. Fast, simulator-free, the
  documented local path. The `Aura` scheme deliberately does **not** list the package's test targets as
  testables, so the package tests are driven through SwiftPM, not the app scheme.
- **Build (×2)** — `xcodebuild build` for `generic/platform=iOS Simulator` and `…/macOS`. Multiplatform
  must compile both ways; these also cover the iOS-only `#if os(iOS)` slice that the host-only unit run
  can't. Separate runners sidestep the per-user process limit that back-to-back local builds hit. Built
  **unsigned** (`CODE_SIGNING_ALLOWED=NO`) — a compile-check needs no signed binary and the runner has no
  signing identity, which the native macOS build otherwise demands ("Mac Development" cert).
- **Snapshot tests** — the app-hosted iOS screenshot suite, isolated in its own gating job on a concrete
  simulator. Kept apart because its rendering is environment-sensitive (the committed PNGs were recorded
  locally; glass/font rasterization can drift past the perceptual tolerance on a different runtime). It
  **gates** by choice; on failure the `.xcresult` (with reference/diff images) is uploaded as an
  artifact, and the fix is to inspect the diff and re-record baselines locally — never record on CI.

This required **sharing the `Aura` scheme** (`xcshareddata/xcschemes/Aura.xcscheme`, committed): it
previously lived only in gitignored `xcuserdata/`, so a fresh CI checkout couldn't resolve `-scheme Aura`.

## Timeline: vertical scrubber on iPhone landscape (compact height)
On iPhone landscape the bottom-floating glass scrubber ate the scarce vertical height and squeezed
the camera grid. There, and only there, the screen splits side-by-side and **hides the nav bar** to
reclaim the title-bar height (the Timeline tab has no toolbar items): a single-column scroll of camera
tiles — each sized to the column's 16:9 height so one fills and the next peeks — on the left, and a
**full-height vertical glass card** (~160pt wide) on the right. The trigger is the real
`verticalSizeClass == .compact`, read directly in `TimelineScreenView` under `#if os(iOS)` (a derived
`EnvironmentValues` accessor was rejected — a computed env property doesn't reliably re-invalidate on
rotation). Compact height means iPhone landscape in practice: iPad reports a regular height in every
orientation and multitasking mode (Split View / Stage Manager make only the *width* compact) and macOS
has no size class, so iPhone portrait, iPad, and macOS all keep the bottom card unchanged.

`ScrollableTimelineView` gained an `axis` parameter so one view serves both orientations, and the
vertical card is kept **visually identical to the horizontal one**: a centered blue-line playhead (no
thumb), the same severity-colored histogram, and the same `Day/Hour/Week` zoom at the **same scale**
(an earlier denser vertical scale smeared the bars into a block). The one deliberate difference is
direction — vertical reads top→bottom as **now→past**, so scrolling **up** moves into the past, with
the live edge under the centered playhead. Motion bars grow rightward from a left-edge time-label
gutter; gaps become hatched horizontal bands.

Two layout gotchas, both verified **on-device** (the snapshot didn't reproduce them): (1) `maxHeight:
.infinity` does not survive `glassEffect` — the glass hugs its content and the histogram collapses — so
the card is sized with a **definite frame measured by a GeometryReader**; (2) the split is driven by
**one outer GeometryReader** with explicit child sizes, because a flexible GeometryReader *sibling* in
the `HStack` collapses both panes.

The `.horizontal` path is byte-identical, so only the **iPhone-landscape** snapshot baselines change —
re-record them locally before merging to `main` (the snapshot CI job gates). The iPhone-landscape
snapshot config also **zeroes the safe area**, because the stock `iPhone13(.landscape)` config applies
portrait-style notch/indicator insets that crush the usable height to a sliver — so the baseline now
matches the on-device height.
