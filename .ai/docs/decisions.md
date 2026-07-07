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
`makeAuthedPlayer`, `platformImage`, and the pinch-zoom gesture container with its clamped zoom/pan
math (see the live-view digital-zoom decision). It's infra-free — `VideoPlayerView` takes
`url + headers`, not a domain type. Cameras/Events/Timeline presentation all depend on it.

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

Coverage was later extended beyond Timeline to the **Cameras grid, Events list, and Settings** screens
(loaded/empty/failed; first-run/saved/error for Settings), through the same matrix runner (renamed
`assertScreenSnapshot` — reference file names derive from the call-site test, so the rename didn't
invalidate baselines). Recording surfaced two things. (1) The grid/list self-load flashed a full-screen spinner on every
re-appearance: `.task { load() }` reset state to `.loading` before fetching, so the first baselines
captured the spinner — and real tab switches flashed it too. The fix is a **refresh-in-place `load()`**
(chosen over Timeline's skip-if-loaded `loadIfNeeded()`, so content also stays fresh): only the very
first load shows the spinner (the initial state), a re-appearance re-fetches behind the current
content, and a failed refresh keeps the last good content instead of a full-screen error — both
behaviors unit-tested in the package.
(2) The reference PNGs must be **excluded from the test bundle**: the synchronized `AuraTests` group
copies every file as a flattened resource, and suites that reuse the same given/when/then test names
produce identically-named PNGs → "Multiple commands produce". The fix is `explicitFolders` +
`membershipExceptions` for `__Snapshots__` on the synchronized group — a folder path in
`membershipExceptions` alone does nothing; the folder must first be an explicit folder reference to be
excludable as one node. Nothing is lost: `swift-snapshot-testing` reads references from the source tree
via `#filePath`, never from the bundle.

One more capture limit (verified with a layer-rendering probe, not assumed): **`SecureField` content
never renders through `drawHierarchyInKeyWindow`** — iOS excludes `isSecureTextEntry` fields from
window/screenshot capture for privacy, and that's the capture path the suite needs for Liquid Glass.
The saved-Settings baseline therefore shows a blank password field on purpose (plain layer rendering
shows the bullets, but can't render glass).

## Test doubles: one shared `TestDoubles` target, every double a `FakeXxx`
All handwritten doubles live in a single **`TestDoubles` package target** (`Tests/TestDoubles`, one
public fake per file), exported as a **test-only library product** — linked by every package test
target and by the app-hosted `AuraTests`, and deliberately not part of the `AuraKit` product, so it
never reaches the app (same rule as `swift-snapshot-testing`). This replaced a zoo of per-file private
doubles (`Stub…`, `No…`, `Empty…`, `Counting…`, `Recording…`, three copies of `FakeHttpClient`): one
configurable `FakeXxx` per protocol — constructor-configured, with invocation tracking only where a
test asserts on it (`fetchCount`, `queriedRanges`, `lastRequest`) — replaces all its variants. One
shared target was chosen over per-feature fixtures modules (the Gradle `testFixtures` shape) because
the fakes are tiny and a solo project doesn't need five more targets. Exception: a fake for an
**internal** protocol (`FakePreviewScrubber` for the Timeline scrubber) stays private in the owning
test target — the shared target can't see the protocol.

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

## Live view: digital pinch-zoom via a gesture container over the platform players
Pinch-to-zoom + pan on the live camera detail is a SwiftUI **gesture container in `CommonPlayer`
wrapped around the untouched platform players** — not a custom `AVPlayerLayer` host (which would
forfeit `AVPlayerViewController`'s free PiP) and not per-platform recognizers. One platform-neutral
implementation covers touch pinch (iOS) and trackpad magnify (macOS). The zoom/pan geometry is a
**pure, clamped value type** — anchor-preserving magnify (1x–4x), pan bounded so the content edges
never pull inside the viewport, double-tap toggling 1x↔2x at the tap point — unit-tested in the
package (`CommonPlayerTests`, the target's first test suite); the gesture wiring stays thin and
untested. All gestures attach as `simultaneousGesture` so the player's own tap-to-toggle-controls
and PiP are never blocked, and because a pinch fires the magnify and drag gestures **together**,
both cumulative values compose against one shared gesture-start baseline (not last-writer-wins,
which jitters). Drag is inert at 1x so navigation swipe-back keeps working; a size change (rotation)
re-clamps the offset through the same math. Fallback if SwiftUI gestures ever fail to reach through
a hosted player view: recognizers in the platform wrappers' coordinators feeding the same math —
not needed so far.

## No XCUITest target — removed the template `AuraUITests`
The `AuraUITests` target (untouched Xcode-template boilerplate: `testExample`,
`testLaunchPerformance`, `testLaunch` — no real assertions) was deleted from the project and the
shared scheme. On Xcode Cloud's **macOS** test action all three failed with *"Failed to activate
application … (current state: Running Background)"* — a documented headless-runner limitation
(XCUITest must bring the app frontmost, and the runner has no foreground GUI session; Apple
Developer Forums threads 695583 / 721005 / 748570), not an app bug. The tests added no coverage
worth keeping: launch-crash detection already comes free from the app-hosted `AuraTests` suite
(its 6 tests can only run if the `Aura` host app launches, on both platforms), and screen
rendering is covered by the snapshot suite. Skipping via `XCTSkip` on macOS was rejected — it
would keep dead XCTest code (the project tests with Swift Testing) for zero remaining value.
If real UI-flow tests are ever wanted, add a fresh target then; don't expect XCUITest activation
to work on hosted macOS runners.

## Camera ordering: a Settings preference, observed reactively (decided, pre-implementation)
User-defined camera order must apply to every camera list (grid, Timeline, future consumers). It is
a **Settings preference**: `[CameraName]` stored on the one `SettingsRepository` (UserDefaults,
per-device like theme). A per-preference `CameraOrderRepository` was rejected — **repositories are
per entity/aggregate, never per function/preference**. Since `SettingsDomain` now needs `CameraName`,
the cross-feature camera entities move to a pure **`CamerasEntities`** target (zero dependencies,
owned by the Cameras vertical: `CameraName`, `CameraStreamSource`) that other features import —
superseding the Events-era "pure domain→domain dependency, no shared kernel" pattern. Entity modules
are **per-feature** (`<Feature>Entities`), never one global `Entities` kernel — ownership stays with
the feature. This also breaks the dependency cycle the old pattern would create
(`SettingsDomain → CamerasDomain` for the type while `CamerasDomain → SettingsDomain` for observing
the preference). Propagation is **reactive, not
manual**: the repository exposes the order as a stream (current value first, then changes);
`ObserveCameras` in `CamerasDomain` composes `GetCameras` with it and emits the sorted list, so
ViewModels just `for await` — no re-apply-on-appear. Sort merge rules: saved names first in saved
order; unknown (new) cameras appended keeping the alphabetical fallback; stale names ignored by the
sort. Editor saves preserve entries for cameras not currently listed (e.g. server-disabled) after
the visible ones — so a disabled camera keeps its slot at the cost of truly-removed names lingering
harmlessly in UserDefaults. Implementation notes: the editor is a Settings sub-screen (`List` +
`.onMove`, **save-on-move** — every drag persists immediately and live screens re-sort behind the
sheet); its row is hidden until a connection exists. ViewModel `load()` still returns after the
first emission (the `.refreshable` spinner contract) and hands the stream to a VM-owned observation
task cancelled in `isolated deinit`; the Timeline keeps a stream-maintained latest-cameras value so
an order change landing during the timeline fetch isn't lost. The snapshot fixtures pass an empty
saved order, so the committed Timeline baselines are unchanged. Implementation notes: the editor is a Settings sub-screen (`List` +
`.onMove`, **save-on-move** — every drag persists immediately and live screens re-sort behind the
sheet); its row is hidden until a connection exists. ViewModel `load()` still returns after the
first emission (the `.refreshable` spinner contract) and hands the stream to a VM-owned observation
task cancelled in `isolated deinit`; the Timeline keeps a stream-maintained latest-cameras value so
an order change landing during the timeline fetch isn't lost. The snapshot fixtures pass an empty
saved order, so the committed Timeline baselines are unchanged.

## Settings is a menu; server config is a sub-screen; theme saves on change
Once Settings held more than the connection form (camera order, appearance), the main screen became
a menu: a **Server** row pushing the connection form (its own Save button — validation errors live
there — popping back on success), the Camera Order row, and the inline theme picker. The theme now
**saves on change** (no Save step on the menu); the toolbar button is **Done**, which closes the
sheet and triggers the root reload (theme + connection identity), same as before. First run (no
connection) shows the same menu — the user opens Server to configure. `SettingsViewModel` slimmed
to theme; the connection form logic moved to a dedicated view model for the sub-screen.

## CI topology: snapshot gate on GitHub Actions only; Xcode Cloud tests via a package scheme; main is PR-gated
Xcode Cloud's test action cannot run the screenshot suite: its tests execute on simulator VMs that
**don't have the source checkout**, and the reference PNGs are deliberately excluded from the test
bundle (see the screenshot-tests decision) — the snapshot library resolves references via
`#filePath` into the build VM's checkout path, so every test fails with *"No reference was found on
disk"* no matter how fresh the baselines are (verified 2026-07: same commit green on GitHub Actions
and locally, red on Xcode Cloud). The **snapshot gate therefore lives on GitHub Actions only**;
don't point Xcode Cloud at the app scheme's tests again without first bundling the references.

Second verified limitation: `xcodebuild` **silently drops Swift package test targets when testing
through the app project's container** — via `.xctestplan` references (either container-path base)
and via a package-owned scheme invoked from the repo root, all ending in *"There are no test
bundles available to test"*. Package tests resolve only in the package's own context. Hence the
shared scheme **`AuraKitTests`** (committed under `AuraKit/.swiftpm/.../xcschemes/`, all package
test targets, build entry on the library product so destinations resolve):
`cd AuraKit && xcodebuild test -scheme AuraKitTests -destination …` — verified green on the iOS
simulator. **Verified 2026-07-07: Xcode Cloud hits the same limitation** — with the workflow's test
actions pointed at the package scheme, both platforms fail with "1 error, 0 test failures" before
any test executes (it resolves the scheme through the app container). Outcome: **Xcode Cloud runs
no test actions** (archive-only workflow); don't re-add one for the package scheme. The scheme
remains useful locally — it's the only way to run the package suites through `xcodebuild` on a
simulator.

`main` is protected by a GitHub ruleset: changes land via pull request with the four GitHub Actions
checks required; direct pushes are blocked. This supersedes the old commit-directly-to-main flow.

## macOS App Store packaging: category key in the shared Info.plist; mac icon slots must be filled
The first macOS delivery (0.2.0 build 9) was rejected by App Store Connect with **ITMS-90242**
(missing `LSApplicationCategoryType`) and **ITMS-90236** (no ICNS app icon). Two packaging rules
follow. The shared Info.plist carries `LSApplicationCategoryType`
(`public.app-category.utilities` — keep it in sync with the App Store Connect primary category;
iOS ignores the key). And **every mac slot of the app-icon set must reference an image**: with the
mac slots empty, the asset compiler emits *no* macOS icon at all — no ICNS and no icon entries in
the compiled catalog (verified by compiling the pre-fix catalog) — which is exactly that rejection.
Verified toolchain behavior (Xcode 26, identical for Debug/Release and with the archive-time
include-all-icons flag): the generated ICNS is deliberately minimal (16pt and 128pt families only)
while the complete set — including the 512pt@2x the rejection names — lands in the compiled asset
catalog; that pairing is the canonical output of every Xcode 26 Mac build, so store validation
accepts it. The mac slot images are `sips` downscales of the 1024px source — regenerate them
whenever the icon artwork changes.
