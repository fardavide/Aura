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
on-device AVPlayer-vs-hls.js spike first; bound windows to ~1h for the nginx-vod segment cap).

### Live-hour tiles: nearest `.webp` preview frame, not a frozen clip (v0.2.2)
Frigate assembles one `preview.mp4` **per completed hour**; the in-progress hour has **no mp4 yet**,
only cached `.webp` preview frames (`/api/preview/{camera}/start/{s}/end/{e}/frames`). The tile
originally loaded clips only, so at the live edge `clip(for:)` found no covering clip and fell back
to the **latest completed clip clamped to its end** — every tile froze on the last frame of the
previous hour (e.g. stuck at ~21:00 when it's 21:45), while the histogram (from `/api/review*`, on
the 30s auto-refresh) stayed current. The already-built-but-unwired frame path is now wired into
`PreviewTileViewModel`: `prepare` also fetches the range's frames (best-effort — a frame-fetch
failure degrades to the old frozen-clip fallback, not a tile error, since the clips already loaded),
and the scrub resolution is **clip-covers-instant → else nearest frame at or before the instant →
else the latest-clip freeze**. A `.frame(Image)` display case renders the decoded webp (immutable,
`URLCache`-friendly). The nearest-frame pick is a pure `[PreviewFrame].mostRecent(atOrBefore:)`
(unit-tested); the image load reuses the existing `PreviewImageLoading` seam, injected into the tile
VM directly (same pattern as the Cameras grid's `CameraImageLoading`, not a use-case wrapper). Frames
were fetched **once per tile on appear** (tiles keyed off `span.start` and didn't reload on the
auto-refresh, by the live-edge-refresh decision), so continuous live-follow without interaction stayed
a follow-up. (The "a scrub picks up newer frames" assumption here was wrong — a scrub only picks among
already-loaded frames — and it surfaced as a real bug; closed in 0.3.3, see the catch-up decision below.)

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

### Timeline catches up on return; tiles live-follow the span (0.3.3)
Reported bug: reopening the app showed the pre-suspension live edge (a "last time" hours old) until a
background tick landed, and the camera tiles stayed frozen at that old instant even after the
histogram refreshed. Three gaps, three fixes — all pinned by view-model tests:
- **The refresh loop only checked after its first sleep**, so a re-entered screen sat stale for up to
  a full interval. It now checks immediately on entry, then sleeps. A scene-active task in the view
  does the same when the app returns from the background (the appearance task doesn't re-fire on
  foregrounding), behind the same should-refresh gate — so it never disturbs a scrub or history
  browsing. That scene task also runs on plain appearance (SwiftUI `.task(id:)` semantics), racing
  the loop's immediate check — so **refresh is single-flight**: concurrent calls coalesce into one
  fetch, which also rules out out-of-order span writes.
- **A refresh never moved the playhead.** After a long suspension the span jumped to the present while
  the playhead stayed hours back: the readout kept the old time, and the live-edge gate then classified
  the user as browsing history, suppressing every further tick. A refresh now moves a playhead that was
  **parked at the old live edge** (within ~a second — sub-second load drift only) to the new one,
  judged **entirely at landing** against the pre-refresh span end. Deliberately much tighter than the
  600s refresh gate, and deliberately at landing: the first draft reused the gate window and a
  pre-await capture, which adversarial review showed would teleport a user re-watching 3–9-minute-old
  footage on every tick, and yank a drag that began *and settled* while the fetch was in flight. An
  active drag at landing always suppresses the follow. (The histogram converges via its own trailing
  re-anchor on content growth — the followed case is precisely the parked-at-the-anchor-edge one; the
  scrubber's scroll→clock binding stays one-way.)
- **Tiles loaded their preview material once** and a span extension never reached them. Tiles now
  re-key their load off the whole span, and a repeated prepare over already-loaded content is an
  **in-place refresh**: clips + frames are refetched, but the active clip/frame is kept, so the playing
  player is not rebuilt (re-fetched clips are value-equal, so the seek path reuses it) and nothing
  flashes. When the load lands it re-applies the **newest requested instant**, not the one captured at
  its start — a scrub arriving mid-refetch wins, instead of the landing snapping every tile back to a
  stale position with no heal path. A transient refetch failure keeps the last good material (frames
  too — pinned by a mutation-killing test) — unlike the first load, which surfaces the error tile; a
  *cancelled* first load (the view re-keyed, tile left the screen) leaves the placeholder rather than
  flashing an error; and a failed tile retries from scratch on the next extension, so tiles
  self-recover with the screen.

Known, accepted exposure: the two view-layer trigger lines — the tile task keyed off the whole span
and the scene-active refresh task — have no automated coverage (package tests can't exercise SwiftUI
task re-keying, and snapshots render one static instant); the view-model behavior they invoke is
fully tested, and the comments at both sites are the guard.

### Timeline tiles stuck on the spinner: the live-edge refresh cancelled the first load (0.3.7)
Reported: on iPhone the timeline "couldn't load" — the camera tiles sat on their loading spinner and
never showed footage. Root cause was the 0.3.3 change above: the tile's load task was re-keyed off the
**whole span** (`.task(id: range)`), and the 30s live-edge auto-refresh advances `span.end` every
tick. Each tick re-keyed the task, so SwiftUI **cancelled the in-flight first load** and restarted it;
the cancel path deliberately leaves the tile on `.loading` (a torn-down fetch is not an error), and
the restart then raced the next tick. A tile whose clip/frame fetch didn't beat the refresh interval —
a slow server, many cameras, a wide preview list — was cancelled just before it resolved, every time,
and spun forever. (Before 0.3.3 the load was keyed off the fixed `span.start` and ran to completion;
the regression was the switch to the mutable whole range.)

Fix: split the tile's two concerns onto **two triggers with different keys**. The first load stays on
`.task(id: range.start)` — `span.start` is fixed for the screen's life, so extending the live edge
(which moves only `span.end`) can no longer cancel it. Following the live edge moves to
`.task(id: range.end)` calling a new `followLiveEdge`, which does nothing while the first load is still
on the spinner (so it can neither race nor duplicate it) and otherwise defers to `prepare` to refresh
material in place or retry a failed tile — preserving every 0.3.3 behavior (live-follow, failed
self-recovery, last-good on a transient failure, latest-instant-wins). Accepted cost: a re-appearance
of an already-loaded tile now runs one redundant in-place refetch (both triggers fire on appear); it's
idempotent (value-equal clips reuse the player) and strictly better than a stranded spinner. This
supersedes the "tile task keyed off the whole span" detail in the 0.3.3 note directly above.

Because `followLiveEdge` reads `.loading` as "first load in flight", the first load must always resolve
to a **non-`.loading`** display or the guard would strand it. Adversarial review found the one path that
didn't: a live-hour first load whose `.webp` frame image fails (clips + frame-list already succeeded)
left the tile on `.loading` — `show` only assigned `.frame` on a successful decode. It now resolves a
failed first-load frame to the `.unavailable` placeholder, so the next extension retries it via
`refreshInPlace` instead of the tile spinning forever whenever the playhead is parked 1–600s behind the
edge (a loaded tile still keeps its last good frame on a transient failure — no flash).

Also hardened the fetch itself: timeline reads now carry a request timeout (`timelineRequestTimeout`,
15s) so a server that accepts a connection but never responds can't hang a load indefinitely — the
best-effort `try?` only catches *errors*, never a silent stall, so the day-timeline overlays (which
gate the whole screen) and a tile's clip/frame list (which gates its spinner) could otherwise block
forever. On a trip an overlay degrades to empty and a tile fails and retries on the next extension.
`followLiveEdge`'s contract is unit-tested (skips while the first load is in flight — including the
held-in-flight regression scenario — refreshes a loaded tile, retries a failed one); the two view
trigger lines themselves stay uncovered for the reason above (package tests can't exercise SwiftUI
task re-keying), so the comments at both sites are the guard.

### Timeline screen stuck on the full-screen spinner: unpinned view model (0.3.9)
Reported: the timeline still "stays loading forever" after the 0.3.7 tile fix. Root cause was
**screen-level**, not tile-level: RootView builds each tab's view model inline in its body, so every
RootView body re-evaluation mints a fresh `TimelineScreenViewModel` born `.loading` — and since the
tab-icon bounce (0.3.2), every tab switch guarantees two body passes (`selectedTab` write, then the
`onChange` bounce-counter bump). `TimelineScreenView` held the model as a plain `let`, so a body pass
landing after the appearance `.task`s started swapped the *displayed* model for a never-loaded one
while `loadIfNeeded`/`autoRefresh` kept driving the discarded instance (an un-keyed `.task` rebinds
only on an appearance, not on a view-value change). The stranded `.loading` model is absorbing: the
periodic tick never reaches it — the un-keyed autoRefresh task keeps ticking against the discarded,
invisibly-`.ready` instance — and the scene-activation catch-up, the one task that *does* rebind
(keyed off `scenePhase`), is gated off exactly in the stuck state because `shouldRefreshNow`
returns false for `.loading`; only an app relaunch recovered. Adversarial verification reproduced it in a minimal
harness: on **macOS** the task/onChange ordering strands the screen on every visit including the
first; on iOS the passes usually coalesce before the task starts, degrading to a spinner-flash +
full refetch per revisit (silently defeating `loadIfNeeded`'s purpose). Cameras and Events were
immune all along — they pin their view model with `@State(initialValue:)`.

Fix: pin the view model in `@State` in `TimelineScreenView`, exactly like the sibling tabs — the
first instance survives for the view's identity lifetime, so the displayed and task-driven model are
always the same object; a connection change still rebuilds it through RootView's `.id`. **The rule
is general: a view that receives an `@Observable` view model and runs `.task` work against it must
pin it in `@State`** (recorded in the swift-style skill). Deliberately *not* changed:
`shouldRefreshNow` still excludes `.loading` (with the pin, `loadIfNeeded` is again the guaranteed
exit, and letting refresh race the initial load would double-fetch), and RootView still mints
throwaway models per body pass (the sibling tabs accept the same cost; caching in the composition
root would add lifecycle concerns for no user-visible gain). Also hardened for parity with 0.3.7:
the cameras `/api/config` read — which gates the Timeline's first paint ahead of the timeline
fetches — now carries the same 15s request timeout (pinned by a repository test), so an
accepting-but-unresponsive server fails into `.failed` (which auto-refresh retries) instead of
holding the spinner for URLSession's 60s default per attempt.

Known, accepted exposures (verified real but rare, not this bug): `URLRequest.timeoutInterval` is an
*idle* timer, so a proxy dribbling ≥1 byte per window evades both this and the 0.3.7 timeouts
(bounding wall-clock needs a session-level `timeoutIntervalForResource`); and `/api/review` is
queried over the full 7-day span with no `limit`, so first paint pays for an unbounded review payload
on event-dense deployments. **Both closed in 0.3.11 (below).**

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
  **gates** by choice; on failure a small **HTML diff report** is uploaded as an artifact (see the
  snapshot-artifact decision below), and the fix is to inspect the diff and re-record baselines locally
  — never record on CI.

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
**pure, clamped value type** — anchor-preserving magnify (1x–10x), pan bounded so the content edges
never pull inside the viewport, double-tap toggling 1x↔2x at the tap point — unit-tested in the
package (`CommonPlayerTests`, the target's first test suite); the gesture wiring stays thin and
untested. All gestures attach as `simultaneousGesture` so the player's own tap-to-toggle-controls
and PiP are never blocked, and because a pinch fires the magnify and drag gestures **together**,
both cumulative values compose against one shared gesture-start baseline (not last-writer-wins,
which jitters). Drag is inert at 1x so navigation swipe-back keeps working; a size change (rotation)
re-clamps the offset through the same math. Fallback if SwiftUI gestures ever fail to reach through
a hosted player view: recognizers in the platform wrappers' coordinators feeding the same math —
not needed so far.

On iOS one thing *did* have to be neutralized: `AVPlayerViewController` installs its **own** pinch
(video aspect fit↔fill) and double-tap zoom recognizers on private descendant views, which raced the
container's gestures — the built-in pinch gave a second, **center-anchored** zoom that desynced the
clamped pan and made the right pinch hard to land (the v0.2.3 anchor fix was downstream of, and
invisible under, this). There's no public API to disable it, so the iOS wrapper walks
`AVPlayerViewController.view`'s subtree and disables every `UIPinchGestureRecognizer` and two-tap
`UITapGestureRecognizer`, re-asserting in `updateUIViewController` since AVKit adds them lazily;
single-tap controls and the PiP button stay live. macOS's `AVPlayerView` has no such on-glass gesture,
so it's iOS-only (v0.2.4, verified on device — this hosted-recognizer conflict can't surface in the
package or snapshot tests).

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

## Snapshot failure artifact: an HTML diff report, not the raw `.xcresult`
A red snapshot job used to upload the whole `TestResults.xcresult` — ~60 MB of hundreds of opaque
files, useless to eyeball. Instead the CI now uploads a small **self-contained HTML report** showing
only the screens that didn't match: expected (baseline) vs actual (this run) side by side, plus an
in-browser **difference blend** (`mix-blend-mode: difference` over black, so only changed pixels light
up) with an amplify toggle. It reads without Xcode, and across the whole matrix a reviewer sees at a
glance which device/orientation/scheme drifted. Mechanism: `swift-snapshot-testing` writes the
freshly-rendered image on a mismatch to `$SNAPSHOT_ARTIFACTS/<Suite>/<name>.png` — by default a
per-run temp dir **inside the simulator's data container** (effectively unreachable). `SnapshotSupport`
pins `SNAPSHOT_ARTIFACTS` to `AuraTests/__SnapshotFailures__/` (derived from the test's `#filePath`, so
it's correct on any machine, and only if the caller hasn't already set it), which mirrors the
`__Snapshots__/<Suite>/<name>.png` baseline layout **at the same relative path** — so pairing
expected↔actual is a path swap, no `.xcresult` parsing and no attachment-name guessing. A dependency-free
`.github/scripts/snapshot-report.py` builds the report from those two folders; the failures folder is
gitignored. This is also a local DX win: a failing run now leaves a tidy folder of exactly what rendered,
beside the baselines. It handles a brand-new snapshot (no baseline) and the no-mismatch case (build/crash,
not a pixel diff) gracefully. The `.xcresult` is no longer uploaded; deep-log debugging falls back to the
job log or re-running locally.

## macOS Settings: grouped Forms + an explicitly sized sheet
On iOS a `Form` defaults to the inset-grouped look; on macOS it defaults to the *columnar* style
(right-aligned labels in a narrow column, no grouped cards, tight spacing) — which read as unpolished
on the native Mac build. The Settings menu and its Server sub-screen therefore pin `.grouped`
explicitly; iOS is unaffected (grouped is already its default, so the snapshot baselines don't move).
Separately, a macOS sheet sizes to its root content's ideal size and does **not** grow when the inner
navigation stack pushes a detail, so the drill-in camera-reorder list rendered with no room and its
cameras didn't show. The Settings sheet now reserves a minimum frame on macOS so pushed details have
space. Neither gap is caught by the suite — macOS snapshots are intentionally excluded (see above), so
the Mac layout is verified by hand.

## Cameras grid v2 restyle: activity badges, live/offline count, size-class layout
The Cameras screen was restyled to the "v2" design concept (`Cameras.dc.html`): dark 16:9 media
tiles with a LIVE marker, the camera name over a bottom scrim, an **activity badge** (alert = red,
detection = amber), an **offline** treatment, and a **live·offline count** pill in the header. The
existing live-video detail (`AVPlayer` + PiP + zoom) is kept — the design's detail overlay (with
"Talk" two-way audio) is a larger separate feature and its live view is already more capable. The
summary card (RIGHT NOW / TODAY / RECORDING) and Outdoor/Indoor group chips are **deferred**: they
need `camera_groups` (in `/api/config`) and `/api/stats`, neither in the verified `/frigate-rest`
map — confirm on-server first. **IR** and the Ken-Burns drift from the mock are dropped: no verified
per-camera IR signal, and the design's own principle is "calm, tiles never move."

- **Tile activity comes from `/api/review`, not `/api/events`.** Review items carry `severity`
  (`alert`/`detection`) directly and `data.objects` for the label; the Cameras feature reads a recent
  review window and keeps the **in-progress** items (`end_time == null`). Kept local to the Cameras
  vertical (its own `ReviewItemDto`), consistent with the feature-vertical rule; a shared Frigate
  review client is a separate roadmap item.
- **Layout by size class**, mirroring Timeline: `verticalSizeClass == .compact` (iPhone landscape) →
  3-up grid; else `horizontalSizeClass == .compact` (iPhone portrait) → 1-column full-width list;
  else (iPad / macOS) → width-adaptive grid. Deterministic per snapshot config.
- **The view model owns preview loading, not the tile.** An earlier pass had each tile self-load its
  still via `.task` and write the offline result back into the `@Observable` view model that the grid
  header reads — that feedback churned the AttributeGraph during the offscreen snapshot render. The
  view model now loads all previews in `load()` (concurrently, so one offline camera can't block the
  rest behind a timeout) and tiles are pure functions of settled state. This also makes the offline
  treatment and the header count deterministic without depending on an async `.task` settling.
- **Concurrent loading requires concurrency-safe fakes.** Loading previews in a `withTaskGroup`
  surfaced a data race in `FakeCameraImageLoader` — an unsynchronized `Array.append` on its recorded
  list corrupted the heap (a `SIGSEGV`/malloc abort that read as a SwiftUI crash). The fake now guards
  its recorded list with a lock. The production loader is a stateless struct, already safe.

## Cameras grid v2 completion: summary card, group chips, 2 s refresh (0.3.1)
The deferred v2 follow-ups (above) shipped after verifying the two blocking endpoints against Frigate
**v0.17.2 source** (the `/frigate-rest` "never guess" fallback) and recording them into the skill +
`frigate-integration.md`. The card has three columns: **RIGHT NOW** (reuses the existing `/api/review`
activity — the most significant current item, alert over detection then recency; tap navigates to that
camera), **TODAY** (`/api/events?after=<start-of-day>`, counted + broken down client-side), and
**RECORDING** (`/api/stats` disk free + `record` retention). Filter **chips** come from `camera_groups`.

- **Kept local to the Cameras vertical.** Each new read has its own Cameras-local DTO + repository +
  use case (`GetCameraGroups`, `GetTodayEventCounts`, `GetRecordingStorage`) — no dependency on the
  Events feature, matching the existing `ReviewItemDto` precedent and the feature-vertical rule.
- **Verified-contract corrections the source bought us.** (1) `camera_groups.<name>.cameras` is
  `Union[str, list[str]]` — the web UI writes a **comma-joined string**, so the DTO decodes both an
  array and a bare string. `birdseye` is stripped (not a real camera). (2) Frigate 0.17 has **no**
  `record.retain.days`; "days kept" is the **max** of `continuous`/`motion`/`alerts.retain`/
  `detections.retain` `.days`. (3) `/api/stats` storage is **MiB** floats keyed by mount path; we read
  the fixed `/media/frigate/recordings` volume, every key optional.
- **Summary is load-time; only stills + activity are on the 2 s loop.** Groups/today/storage refresh on
  load + pull-to-refresh, not the (now 2 s) still-refresh timer — RIGHT NOW still feels live because it
  derives from the activity that *is* on the loop. Every summary piece is **best-effort**: a failed
  fetch just blanks its slot, never failing the grid.
- **Known cost:** the groups read and the storage read each re-fetch the heavy `/api/config` that the
  camera-list read already pulls (≤3 config GETs per screen appearance, load-time only). Consolidating
  the per-screen config reads behind a shared, request-coalescing `FrigateApiClient` is the standing
  roadmap refactor — deliberately not done here to keep the vertical boundaries clean.
- **Byte counts read the SwiftUI environment locale**, not the process locale — `.byteCount` via
  `Foundation` otherwise formats with `Locale.current` (this machine's), which rendered "1,4 TB" and
  would diverge from CI. Reading `@Environment(\.locale)` localizes with the app *and* renders
  deterministically under the snapshot harness's pinned locale. New snapshot state: **summary** (chips +
  populated card + a selected group).

## Animated tab icons: symbol bounce on the system tab bar (0.3.2)
The root tab icons animate with an SF Symbol **bounce** when their tab is selected, on the
**system** tab bar — a custom tab bar (the only way to *guarantee* arbitrary label animation) was
rejected: it would forfeit the free Liquid Glass bar and each platform's own tab presentation
("don't fight the system"). This rode along with migrating the root `TabView` from the pre-iOS-18
`tabItem` (deprecated in the 26 SDKs) to the selection-value `Tab` API with a typed tab enum,
which is worth keeping regardless of the animation. The bounce is keyed on a **per-tab counter**
bumped on selection change, so only the newly selected icon animates — keying on
`selection == tab` also fires on the deselected icon (a discrete symbol effect triggers on *any*
change of its value). **Verified**: `Tab(value:content:label:)` exists (Apple docs); nothing
animates automatically and legacy `tabItem` strips label modifiers (community consensus through
the iOS 18 cycle). **Not yet verified — check on device**: whether the iOS 26 / macOS 26 system
bars honor a symbol effect inside a custom `Tab` label (historically system bars rendered tab
labels themselves and dropped modifiers; packages offering "custom Liquid Glass tab bars" exist
precisely because of this). Failure mode is benign — icons stay static, no regression. If the
effect is stripped and the animation matters, the fallback is a custom bar, a deliberate
trade-off to re-decide then.

## Timeline: macOS/iPad video-wall grid + continuous scrubber zoom (0.3.4)
The Mac timeline read as broken: `GridItem(.adaptive(minimum: 220))` kept tiles at thumbnail size
on a big window (three cameras huddled in a corner of a 27" display), and the only zoom was the
cycling Day/Hour/Week pill — no pinch, and a preset switch kept the raw scroll offset, so the
playhead re-read it as a different time and jumped. Three changes, shared by iPad + macOS
(regular width):

- **Best-fit wall layout.** On regular widths the grid is sized by a pure best-fit (unit-tested):
  try every column count, tile width = min(width limit, height limit × 16/9), keep the largest;
  the wall centers in the space above the scrubber card. If even the best fit drops below the old
  220pt minimum (many cameras / small window) it falls back to minimum-width columns and scrolls,
  so nothing regresses. Compact width (iPhone portrait) keeps the old adaptive column byte-for-byte;
  iPhone landscape keeps the side-by-side split.
- **Continuous zoom, anchored at the playhead.** The scrubber density is a continuous
  points-per-hour clamped to the week…hour preset extremes; `MagnifyGesture` (trackpad pinch on
  macOS, two fingers on iOS) scales it, and the pill shows/cycles the log-space-nearest preset.
  Every zoom change recomputes the current instant's offset through the same pure offset↔instant
  scale the scroll mapping uses and re-anchors via `ScrollPosition.scrollTo` — also fixing the
  pre-existing preset-switch jump. The `ScrollPosition` binding starts idle, so
  `defaultScrollAnchor` still governs the initial live-edge position.
- **Tiles own their 16:9 canvas.** `aspectRatio(.fit)` over non-resizable content (spinner,
  no-footage symbol) collapsed the whole tile to a thin bar — visible in every committed
  ready-state baseline, and on-device whenever a camera has nothing to show. The canvas is now an
  always-flexible black color with the content overlaid, so a placeholder keeps its slot. All
  Timeline ready-state baselines (iPhone + iPad) were re-recorded for this.

## Live view: bare-layer video host + custom controls — reverses "gesture container over the platform players" (0.3.5)
The gesture-container-over-`AVPlayerViewController` approach above had a structural flaw that the
zoom rework surfaced: `scaleEffect` on the hosted player scales the **whole** view — video *and*
AVKit's transport controls — because they're one view hierarchy, so pinching magnified the play
button, volume, and scrubber along with the picture. And the built-in aspect-fit↔fill pinch could
never be *reliably* neutralized: the subtree-walk that disabled `UIPinchGestureRecognizer`/two-tap
recognizers raced AVKit's lazy, asynchronous (re)installation, so the stray center-anchored zoom
still surfaced intermittently. Both are the same root cause — AVKit bundles video + controls +
gestures — so both are fixed by **not hosting the live video in AVKit's player at all**.

The live video is now a **bare `AVPlayerLayer`** host (`LivePlayerView`, `layerClass` on iOS /
`makeBackingLayer` on macOS) that renders *only* the picture — no chrome, no built-in gestures.
That layer is the sole thing inside `ZoomableContainer`, so the zoom scales only the video; the
transport controls (`LiveControlBar` — play/pause, mute, PiP, a LIVE badge, Liquid-Glass capsules)
are an overlay **outside** the container and never scale. With no AVKit chrome there is no
aspect-fill pinch to race, so the subtree-walk suppression is **gone**. `LivePlayerModel`
(`@Observable`) owns the `AVPlayer`, drives PiP via **`AVPictureInPictureController(playerLayer:)`**
(auto-start-on-background on iOS via `canStartPictureInPictureAutomaticallyFromInline`; a manual
button gated on `isPictureInPicturePossible`), and keeps the audio-session interruption recovery
(rebuild a fresh live item at the live edge). This **reverses** the earlier "not a custom
`AVPlayerLayer` host (which would forfeit free PiP)" call: PiP is now app-owned, which costs a small
amount of glue but is the only way to separate video from controls. One cross-platform host serves
iPhone/iPad + macOS, so the controls-scaling bug is fixed on the Mac too (`AVPlayerView`'s inline
controls used to scale as well).

Two lifecycle subtleties, both caught by an adversarial review before shipping: (1) playback and the
interruption observer start from the view's `onAppear` (`start()`), not `init`, and the `AVPlayer`
is **lazy** — otherwise the throwaway `LivePlayerModel` instances SwiftUI builds and discards on
every `LiveVideoView` re-init (the grid's 2 s refresh loop re-renders the pushed detail) would each
open and abandon an authed stream. (2) A floating PiP window must outlive the view that started it;
since the model is the only strong owner of the controller + player, a file-private
`PictureInPictureRetainer` holds the model while its session is active (added on
`didStartPictureInPicture`, removed on stop/fail) so navigating away doesn't kill PiP.
**On-device verification still owed** (like the prior hosted-recognizer work, this can't surface in
the package or snapshot tests): confirm PiP survives a manual start followed by leaving the screen,
and that auto-PiP-on-background still hands back cleanly. The pure `ZoomTransform` math and its
`CommonPlayerTests` are unchanged; the new host is thin platform glue and stays untested by the same
rule as the old wrapper.

## Every Frigate read bounded (15s) through one shared FrigateApiClient (0.3.10)
The 0.3.7/0.3.9 hardening bounded the Timeline reads and the cameras config read; the other five
Cameras data types (groups, storage, activity, today-events, stills) and the whole Events data layer
still rode URLSession's 60s default. First, each remaining read gained the same 15s timeout via TDD —
one `lastRequest.timeoutInterval` test per repository/loader against the shared `FakeHttpClient`.
Then the thrice-duplicated authed-GET ladder (Basic auth + timeout + status→error mapping) was
extracted into **`FrigateApiClient` in `CommonFrigate`** — the standing status.md refactor, done as
the refactor step of those cycles. Shape decisions:

- The client throws a **transport-vocabulary `FrigateApiError`** (unreachable / notAuthorized /
  serverUnavailable / unknown); each feature's Data layer maps it into its own domain error with an
  exhaustive-switch initializer at the boundary (shared internal mapper in `CamerasData` — six
  consumers; file-private in the single Events/Timeline consumer files). Domains keep owning their
  errors; Frigate vocabulary still never crosses the Data boundary. Best-effort media loaders just
  `try?` the client, which collapses their hand-rolled status checks.
- Repository/loader **init signatures are unchanged** (`config:httpClient:` — each builds its client
  internally), so the composition root and every existing test stood still; the per-repo timeout,
  auth-header, and status-mapping tests keep pinning the behavior through the public APIs.
- `CommonFrigate` gained the **`CommonNetwork` dependency edge** the architecture docs had always
  drawn (`Data → CommonFrigate → CommonNetwork`) but the manifest never needed until now.
  `TimelineHttp.swift` dissolved into the client and its two consumers.
- The timeout is an **idle** timeout (resets whenever bytes arrive), so it also guards the media
  loads (stills, thumbnails, clip downloads) without capping a large clip on a slow link.
- Deliberately **not** the request-coalescing client from the 0.3.1 known-cost note — the ≤3
  `/api/config` GETs per grid appearance remain; that consolidation stays on the roadmap, and the
  client is now the natural seam to add it behind.

## Closing the two 0.3.9 exposures: capped review + wall-clock timeout (0.3.11)
The 0.3.9 note logged two verified-but-rare exposures as candidates for a later pass; this is that
pass. Neither is a live bug — both are hardening against pathological deployments/connections.

- **`/api/review` now carries a required `limit`.** The builder (`FrigateReviewUrl.review`) took no
  `limit`, so first paint's day-timeline markers fetched *every* review item in the 7-day span — an
  unbounded payload on an event-dense server, gating the screen behind it. `limit` is now a
  **required** parameter (no init default — a new call site must choose one), so the omission can't
  recur silently: the day timeline caps at 1000 markers, the Cameras activity read at 100. Frigate
  orders review items **severity asc then start_time desc**, so truncation drops the *oldest
  detections* first — every alert and the newest activity survive, and overall density still reads
  through the motion strip. Pinned by a repository test that routes the review body only to the
  capped URL (an uncapped query falls through to a marker-less body — avoids racing the three
  concurrent overlay fetches for one `lastRequest`) and an exact-URL activity test.
- **`UrlSessionHttpClient` now bounds wall-clock transfer time.** The 0.3.7/0.3.9/0.3.10 timeouts
  are all `URLRequest.timeoutInterval`, an **idle** timer — a proxy dribbling ≥1 byte per window
  resets it forever and holds a gating load open. The client now builds its own `URLSession` from a
  `.default` configuration with **`timeoutIntervalForResource = 600s`**, a whole-transfer ceiling the
  idle timer can't evade. 600s is deliberately generous: it must never abort the largest legitimate
  transfer on this session — a full event `clip.mp4` downloaded for playback over a slow remote link
  — while still ending a genuine stall. (Scrub/live playback rides AVFoundation's own sessions, not
  this one, so the cap doesn't touch HLS/VOD.) The injectable `session:` init param was dropped —
  only the composition root constructs the client, and an injected `.shared` would have silently
  bypassed the bound; `session` is now `internal` so a `CommonNetworkTests` test can pin the
  configured resource timeout.

## One shared, self-refreshing `/api/config` read (0.3.12)
This closes the standing "consolidate the per-screen `/api/config` reads behind request coalescing"
follow-up (0.3.1 known cost, re-noted in 0.3.10) — but **not** with request coalescing, which would
have collapsed nothing: the grid issues its three config reads **sequentially** (the camera list
gates first paint, then the summary's groups and retention), so they never overlap and there is no
concurrent duplicate to de-dupe. What they need is a shared *value*.

A `FrigateConfigProvider` actor (in `CamerasData`, since all three readers are Cameras-owned) holds
the one config body and hands out slices of it. It serves the raw `Data`, not a parsed model, so each
reader keeps decoding its own DTO (`ConfigDto` / `GroupsConfigDto` / `RecordConfigDto`) and the
feature-vertical DTO ownership is untouched. A grid load now costs **one** `/api/config` GET instead
of three — pinned by a test that drives the three readers in load order and counts config requests.

Shape decisions, several of them forced by adversarial reasoning about failure paths:
- **Reactive, not a short-lived cache.** The provider re-reads every 2 minutes and *pushes* to
  subscribers, so `camera_groups` and the retention figures follow a server-side change while the
  grid is open — previously load-time only. The cadence is tied to subscription lifetime (one loop
  serves every observer; it starts on the first and is cancelled with the last), so a closed screen
  stops polling. Chosen over the simpler read-through cache because it fits the existing
  "preferences are observed, not polled" rule and removes staleness rather than merely bounding it.
- **The camera list deliberately does *not* take the cached copy.** It calls a `reloadConfig()` that
  always hits the server, because it is the read behind pull-to-refresh and must reflect the server
  as of now. This costs nothing: the reload broadcasts, so the summary observers refresh off it, and
  it still coalesces with any fetch in flight — a screen load stays at one request either way.
- **The config stream carries `Result`, not just successes.** The first draft emitted only successful
  bodies so subscribers would "keep the last good value" on a trip. That is a deadlock: a view model
  awaiting its first value on an unreachable server would wait forever. Failures are emitted, and
  each repository decides what one means — **the first failure resolves to an empty slot** (no chips
  / no storage figures, exactly the old best-effort behavior, so the screen is never gated on a
  broken read), while **a later failure emits nothing at all**, leaving what is on screen in place
  instead of blanking it mid-session. Both halves are pinned by tests, the "later failure" one by
  asserting the *next* value is a third read's data rather than an empty emission.
- **Groups and storage became `Observe…` use cases**, with the repository protocols streaming;
  storage streams an `Optional` because a blank card slot is a real state. `CamerasRepository` /
  `GetCameras` / `ObserveCameras` are untouched — the camera list stays one-shot, since the list
  effectively never changes at runtime and leaving that well-tested path alone kept the blast radius
  small. `GetTodayEventCounts` stays one-shot too (it reads `/api/events`, not the config).
- The view model still **awaits the first emission** of each observation before `load()` returns, so
  a settled load still means a settled screen — what the snapshot suite and the pull-to-refresh
  spinner both depend on. Its two observation tasks are cancelled in the existing `isolated deinit`,
  and each clears itself when its stream ends so a later `load()` re-subscribes.

Accepted cost, unchanged from before: `RootView` still mints a throwaway view model — and now a
throwaway provider — per body pass. A provider does no work until something subscribes, so an
unused one is inert.

## Full-resolution recordings playback: wall-clock ↔ player-time mapping (v0.3.13)
Tapping a Timeline tile now pushes a single-camera player over the recorded stream
(`/vod/{camera}/start/{s}/end/{e}/master.m3u8`), closing the "deferred to 0.1.5" item above. The
grid keeps its low-res preview scrubbing — that is what Frigate's own web client does, and a wall of
full-res HLS streams is not viable on a phone; full resolution lives on the pushed screen.

Three decisions carry the feature:

- **Player time is not wall-clock time, and the gap between them is computed, not guessed.** The
  server welds a window's recordings into one continuous stream with the gaps removed (verified
  against the v0.17.2 VOD handler: one `sequences` entry, `discontinuity` off). So a seek to
  "14:32:10" has to be converted by summing the footage before it. `RecordingTimeline` (pure,
  Domain) owns that in both directions and replicates the server's own clip rules — trim each
  segment's **reported duration** by the window overhang, then drop what falls under 100 ms or
  reaches 600 s (`MAX_SEGMENT_DURATION`). It follows the reported `duration`, never
  `end - start`: the server builds each clip from the duration, and the two differ in practice.
  Both mappings are **total** — an instant inside a gap resolves to the gap's trailing edge, since
  that is genuinely where playback resumes — with `hasFootage(at:)` as the separate question the UI
  asks so it can say "no footage" instead of silently showing a different moment.
- **One clock hour per window, and the hour is also the window's *identity*.** `MAX_PLAYLIST_SECONDS`
  is 7200, so a whole day in one playlist is out; Frigate's client chunks by the hour and this does
  the same. Crucially `RecordingWindow.containing` takes **no clock** — it returns the whole hour,
  never one clamped to the present. The first draft clamped the end to `now`, which made the
  in-progress hour a *different window every second*: an adversarial review caught that every skip
  then refetched and rebuilt the player, and that reaching the end of the stream reloaded the same
  hour and **rewound to the top of it**, forever. The unit tests all passed because they froze the
  clock — the regressions now drive a clock the test winds forward, and the live edge is recognised
  by "the next hour hasn't happened yet" rather than by the window looking different.
- **Skipping moves in stream time, not wall-clock time.** Ten seconds back means ten seconds of
  footage back, so a skip steps over a gap instead of stalling at its near edge — mapping a
  wall-clock target that lands inside a gap resolves *forward*, which made backward skips out of a
  gap a no-op. Running off either end of the window continues into the neighbouring hour.
- **Transport drives `rate`, not `play()`/`pause()`.** Resuming at 4× would otherwise briefly run at
  1× before the rate reapplied. Play intent is read when a load *lands*, not captured when it is
  issued, so a pause taken while a window was fetching isn't undone; loads carry a generation stamp
  so a slow one that lands after a newer seek is dropped rather than yanking the playhead back.

Unverifiable here, and the one real risk: **AVPlayer against Frigate's VOD HLS is still unproven.**
Frigate's client sets `USE_NATIVE_HLS = false` on every platform and always uses hls.js, so nothing
upstream exercises the native path. Everything above is source-accurate and unit-tested, but whether
`AVURLAsset` loads the playlist, seeks exactly within it, and honours a pre-roll seek needs a check
against the running server. Two smaller unknowns ride along: HLS **segment** sub-requests may not
carry `AVURLAssetHTTPHeaderFieldsKey` (moot on the unauthenticated port 5000 default, not moot
behind a Basic-auth proxy), and the server snaps a head-trimmed clip back to the preceding keyframe
and adds the gained milliseconds to its duration — a blind spot the client cannot see and Frigate's
own client shares, bounded by one GOP and reset at each window.

Snapshot-tested the way the live player already is: recorded video can't render offscreen, so the
transport is split into a `RecordingControlState` value + a bar that is a pure function of it, and
the layout is captured over a black placeholder with no `AVPlayer` built. Three states (playing,
paused at 8×, an hour with no footage) across the device + light/dark matrix.

## Timeline transport + full-resolution tiles — reverses "the grid keeps its previews" (0.4.0)
The scrubber card gained the transport the design has always carried (`Timeline.dc.html`, Option A:
skip ±10s, play/pause, the 1–8× ladder), and pressing play now swaps **every** tile from the low-res
scrub material to that camera's own recording. This **reverses** the 0.3.13 decision above, which
kept full resolution on the pushed single-camera screen because "a wall of full-res HLS streams is
not viable on a phone". That reasoning was written against an unbounded camera count; the user chose
the literal behaviour with the cost understood (`.ai/plan/no-ticket_timeline-transport-fullres/`,
Option 1 of three — the alternatives were a single focused tile, or a cap on how many tiles stream).

Four decisions carry it:

- **Playback is a clock, not a player.** `TimelineTransport` advances the one shared `ScrubClock`
  that the histogram, the readout and every tile already follow; nothing about it streams anything.
  The grid therefore stays synchronised **by construction** rather than by keeping N players in step
  with one another — the alternative (a designated master player others chase) would have made the
  readout disagree with the picture whenever the master stalled. Tiles are followers: each corrects
  its own stream when it drifts more than a second from the clock, and swaps hours when the playhead
  leaves the one it is streaming. Drift between tiles is real and accepted; drift between the clock
  and what the card *says* is not possible.
- **Playing scrolls the histogram; it does not move the playhead.** The playhead is fixed at the
  centre by design, so "the clock advanced" and "the track slid past" are the same event. While
  playing, the clock leads and the scroll follows it, and the scroll→clock direction is switched
  off — reading the time back out of an offset we just wrote fed rounding error into the playhead.
  The user taking hold of the scrubber pauses playback (on the gesture-driven scroll phases only:
  `.animating` is our own re-anchor and must not pause itself).
- **Gaps are stepped over, the live edge stops playback, and play from the edge rewinds a minute.**
  Sitting inside a gap would show every tile the same frozen frame for as long as it lasts, which
  reads as a hung player, so `TimelinePlayhead` (pure) jumps to the far side — ascending order, so
  adjacent gaps clear in one pass. Nothing is recorded past the live edge, so playback stops there;
  pressing play while parked on it backs up a minute rather than stopping again on the first tick,
  which also closes the "Play does nothing at the live edge" follow-up left open in 0.3.13.
- **An hour with no footage is not a tile failure.** A tile whose hour holds nothing playable — or
  whose read failed — falls back to its preview material and records that hour as abandoned, so the
  follow doesn't refetch it on every one of the ~10 ticks a second; it rejoins full resolution at the
  next hour that has footage. Playback carries on around it either way. The tile keeps `isPlaying`
  separately from "is streaming" for exactly this reason.

`RecordingWindow`/`RecordingTimeline`/`GetCameraRecordings` are reused unchanged from 0.3.13 — the
tile is a second consumer of the same wall-clock↔player-time machinery, so the hour-window rules and
the gap mapping have one implementation, not two.

The 0.3.13 risk carries over **multiplied**: AVPlayer against Frigate's VOD HLS is still unproven on
a real server, and this now opens N of those streams at once rather than one. Two things to watch on
the running instance: total bitrate at the real camera count, and whether 4×/8× produces smooth
playback at all (nginx-vod-module is not known to publish I-frame-only playlists, so a high `rate`
may degrade to stepping). The transport clock is correct regardless of what the streams manage.

Snapshot coverage adds a **playing** state (transport showing pause at 4×) to the timeline suite.
It is deterministic because `now` is injected and frozen: `run()` measures real elapsed time, which
is zero against a frozen clock, so the tick loop can't advance the playhead mid-capture.

## Timeline detail: one camera on its own time axis (0.5.0)
`Timeline Detail.dc.html` (Claude Design) applies to the screen a tile push opens — one camera, one
time axis, playhead fixed at the centre. The user scoped this to the **core screen**: the mock's
activity list, its Hour-zoom preview filmstrip and its Save-frame / Clip-export actions are
deliberately out, and so is the `IR` badge (Frigate exposes no day/night flag; the mock fakes it with
a CSS filter) and the discrete `1× / 2× / 4×` digital-zoom chip (the live view's `ZoomableContainer`
gesture already covers that capability).

- **Timeline reads are scoped by a `TimelineScope` enum, not an optional camera.** `allCameras` (the
  tab) and `camera(name)` (the detail) are both named states, so no caller has to interpret a `nil`.
  The Data layer maps the scope to a `cameras=` query on all three review endpoints and **omits the
  param entirely** for all-cameras — `cameras=all` is only documented for `/api/events`, and omission
  is the shape already proven in production.
- **The detail track is centre-anchored (`TimelineViewport`), not scroll-offset (`TimelineScale`).**
  The tab's track lives in a `ScrollView`, so its geometry is a function of a scroll offset. This one
  has to drive an `AVPlayer` seek from a drag, which a scroll offset models badly — so the viewport is
  a pure function of the playhead instant, the density and the measured length, and the drag is
  *anchored* (instant at gesture start + total translation) rather than summing deltas. Both types
  stay; they answer different questions.
- **Scrubbing seeks within the loaded hour and defers the window swap to the release.** A drag that
  leaves the hour would otherwise fetch a playlist per drag frame. In-hour seeks are tolerant (±0.5s,
  cheap); the settle on release is exact. The readout follows the finger throughout.
- **The readout keeps the instant asked for, even inside a gap.** The stream welds gaps away, so
  reading the position back off the player would collapse a gap-side instant onto the footage that
  actually resumes there and quietly report the wrong time. The periodic time observer therefore
  updates the readout **only while playing** — paused, the playhead belongs to whoever positioned it.
- **The day-overview bar is derived, not fetched.** `DayOverview` rolls the already-loaded motion
  buckets into 24 hourly means (mean, not peak — a peak saturates on one burst). Frigate's own
  `/api/{camera}/recordings/summary` would be a second round trip per day step for the same picture.
  The bar's mean and the track's bars share one measured axis length so the outlined window is honest.
- **Motion bars are drawn at the resolution of the data.** Bucket width comes from the buckets
  themselves (the server picks the scale from the span — ~5 min over a 7-day span), not from a
  constant. The mock's fine-grained bars are generated data; pretending to that resolution would be a
  false claim about the footage.
- **Three arrangements, chosen by size class exactly as `TimelineScreenView` already does.** Compact
  height → the mock's full-bleed footage plus a 168pt vertical rail; compact width → the panel floats
  over the bottom on glass; regular width (iPad, macOS) → the mock's hero with the panel spread wide
  beneath it. The phone-upright case departs from the mock, which puts the panel *below* a fixed-height
  hero with the activity list under it: without that list the layout would leave a third of the screen
  empty, so the panel floats instead — the app's established language (the Timeline tab, the live view).
- **The hero chrome renders against a forced dark color scheme.** The hero is a dark surface whatever
  the app's appearance — the footage is, and so is the black it falls back to — so resolving
  `primary`/`secondary`/`thinMaterial` against dark is what keeps the badges and the no-footage state
  legible in a light-mode app.

`RecordingControlBar` / `RecordingControlState` / `RecordingPlayerLayout` are superseded by
`RecordingTransportBar` / `RecordingDetailState` + `RecordingDetailActions` / `RecordingDetailLayout`.
The screenshot suite grew from 3 states to 5 and covers all three arrangements through the existing
device matrix; baselines were re-recorded locally and inspected.

## Screenshot tolerance: widen the per-pixel threshold, keep the area budget (0.5.0)
The recording-player suite went red on CI while passing locally. Chasing it produced two wrong
answers before the right one, both worth recording so the next person doesn't repeat them.

**Wrong answer 1 — "the renders differ".** They don't, much. The CI captures match the committed
baselines to 9 pixels out of 2.96M (iPhone portrait) and 11 of 8.96M (iPad landscape), worst channel
delta 1/255. Note the baselines are **16-bit Display P3**: `sips`, BMP conversion and every other
8-bit tool silently truncate them and will report a pair as identical when it isn't. Decode at 16
bits or don't bother.

**Wrong answer 2 — "so drop the perceptual comparator".** `perceptualPrecision < 1` does route
`compare` through Core Image with colour management disabled, and the library's own source warns that
virtualized hardware without a GPU "falls back to a CPU-based OpenGL ES renderer that silently fails
when a Metal command is issued" — every GitHub-hosted runner. But switching to the byte branch
(`perceptualPrecision = 1`) fails **locally**: re-rendering an iPad frame redraws ~26% of it — the
whole Liquid-Glass panel — by 1–15/255, while the text and shapes drawn *on* the glass stay stable.
Glass is genuinely not deterministic, which is exactly why the perceptual tolerance was there.

**The fix** is to spend the tolerance on the right axis. `perceptualPrecision` sets the per-pixel ΔE
threshold ((1 - value) × 100); `precision` is the fraction of pixels allowed to exceed it. The glass
drift is a per-pixel problem, so the threshold moves — 0.95 → **0.87**, i.e. ΔE 5 → 13, clearing both
the local drift and the ~10.1 worst pixel the GPU-less runner scored. The area budget `precision`
stays at **0.98**: that is the real gate, and a moved control, a wrong colour or dropped text exceeds
ΔE 13 across far more than 2% of a frame. No baselines were re-recorded.

The cost, stated plainly: a regression that shifts colour by less than ΔE 13 without moving anything
is now invisible. Glass forces that trade — the alternative is a gate whose verdict depends on
whether the machine running it has a GPU.

## Timeline overlays: day-sized sequential windows + live-edge delta refresh (0.5.1)
Field report: opening the Timeline took the user's Frigate server down for a while — the web UI
"offline", the Home Assistant entity Unavailable — and playback on the new detail screen never got
a chance to start. The cause is server-side but the client was pulling the trigger: Frigate 0.17's
`/api/recordings/unavailable` handler is an `async def` that scans the window's recording rows once
per bucket **on the API's event loop** (`no_recordings`, `frigate/api/media.py`, verified v0.17.2 —
details in `frigate-integration.md`). Our 7-day × ~2000-bucket query froze the entire API for tens
of seconds per call on a modest machine; the tab re-issued it every 30s at the live edge, and 0.5.0
added the detail screen doing the same **ungated**, every 30s, even while browsing history. The
client's own 15s timeout makes it worse, not better: uvicorn grinds each abandoned request to
completion while the next tick queues another.

The fix keeps the feature and re-shapes the traffic:

- **Overlay reads are windowed to at most a day and issued sequentially, newest first**
  (`OverlayWindow.windows`; the `GetDayTimeline` use case now returns an `AsyncStream` of
  `DayTimelineSlice`s). Cost of the quadratic endpoint drops roughly linearly with the window
  count, each event-loop hold shrinks from tens of seconds to sub-second, and the server breathes
  between windows — HA polls keep answering. The walk **stops at the first failed window** (the
  repository throws only when *all three* endpoints fail — one failing endpoint still degrades to
  empty, per the 0.1.4 best-effort rule) so an unreachable server isn't asked for six more days.
  Coverage is tracked as a suffix (`overlaysLoadedBack`) and the next refresh resumes the walk.
- **The strip's resolution is pinned from the full span** (`OverlayWindow.bucketDuration`, floored
  to whole seconds) and passed through the repository per window — per-window derivation would
  have made a day-window read come back at 60s buckets, 5× the rows *and* mixed bar widths.
- **A periodic refresh re-reads only `[previous end − one bucket − 60s, now]`** and merges it in
  place (`DayTimeline.replacing`): slices replace exactly their window — markers by overlap (an
  in-progress marker reaches the present, so any live-edge window supersedes it; `/api/review`'s
  overlap-with-NULL-end clause guarantees the fresh copy is in the response), motion buckets by
  half-open containment, gaps clipped at the seam and re-welded when two windows each hold half.
  Slice content is clipped to its window first — overlap queries answer generously, and the canned
  fakes answer every window identically; without the clip both would duplicate.
- **The detail screen's refresh is now gated at the live edge** exactly like the tab's (browsing
  history re-reads nothing), and **the tab paints its grid before the overlays** — `.ready` with
  empty overlays right after the cameras land, slices streaming in behind — so a server with only
  its activity endpoints down no longer blanks the screen (the repository had always promised
  that; the view model finally honors it). A timeline-fetch failure can no longer fail the screen,
  only a camera failure can — the `.failed`-on-timeline-throw path was unreachable in production
  and is gone.

Deliberately unchanged: the 30s cadence (each tick is now ~200s of data instead of 7 days), the
7-day span, and the `/api/review` per-window `limit` (1000). Known, accepted exposures: motion rows
straddling a window seam belong to neither window's query (`start_time > after AND end_time <
before`), so a seam bucket can read one segment low — invisible at 5-minute buckets; and overlay
history loaded at open is not re-read while the screen stays up, so a server-side review deletion
only disappears on the next screen entry. Fixing the endpoint upstream (bisect + threadpool) is
worth filing with Frigate; until then this access pattern is the contract — recorded in
`/frigate-rest`.

## Timeline detail: top-slot zoomable video, resume-after-scrub, sticky Live, fling, one track language (0.5.2)
A user-reported batch against the 0.5.0 detail screen and the tab scrubber. Ten items; the preview
**thumbnail filmstrip stays deferred** (its own follow-up — thumbnails need `AVAssetImageGenerator`
over the authed preview clips plus a cache, too much rider for this change), and the mock's
Save-frame / Clip-export remain out of scope per the 0.5.0 decision.

- **The video gets a *slot*, laid out — not floated over.** On the phone the footage was centred in
  a full-bleed surface with the glass panel overlaid, so the panel covered its lower half. The
  arrangements are now real stacks: portrait a `VStack` (video slot on top, panel below), landscape
  an `HStack` (slot beside the rail) — the resting picture **cannot** be covered by construction,
  and no `@State` height measurement is involved (a measured panel height settles a pass later,
  which the snapshot suite can't tolerate — the `RecordingScrubTrack` lesson).
- **The detail video zooms like the live view, and overflows its slot on purpose.**
  `ZoomableContainer` (the live view's pinch/pan/double-tap container) now takes an explicit
  `clipsContent`; the phone slots pass `false`, so zoomed footage spills out of the slot and slides
  **under the glass panel** — by design, the panel refracts it — while the iPad hero keeps clipping
  to its rounded frame (nothing overlaps it there). The hero chrome and the panel sit outside the
  container and never scale (the 0.3.5 rule, applied here).
- **The screenshot suite can now *see* the layout contract.** A `cameraAreaHighlights` environment
  flag makes `RecordingDetailLayout` outline the **surface** (orange — everything zoomed footage
  may cover, drawn above the panel since the surface legitimately runs under it) and the **initial
  camera slot** (green — what the controls must never cover). One `detail-areas` snapshot state
  records both, so a panel creeping over the slot turns up in a baseline diff instead of on a phone.
- **Interacting with a timeline resumes the playback it paused.** Both surfaces paused on grab and
  never resumed. `TimelineTransport` gained `beginInteraction`/`endInteraction` (the scroll phases
  report begins repeatedly — the play state is captured only on the first; `pause()` stays for the
  deliberate tile-push stop) and the detail VM does the same for `beginScrub`/`endScrub`, including
  across a caught fling. An explicit play/pause taken mid-drag clears the pending resume — newest
  intent wins. The day-overview bar's drag was a raw exact-`seek` per frame; it now runs the same
  begin/scrub/end trio (cheap tolerant seeks while dragging, exact settle, resume after).
- **"Live" is an intent the view model owns, not a ≤1s instant comparison.** The chip went red on
  `goLive` and grey a second later: the periodic time observer reports the player's true position,
  which parks seconds behind the wall clock (segments land late), and the old
  `span.end − instant ≤ 1s` read that drift as history. `followsLiveEdge` is now set by deliberate
  moves that land on the edge (goLive, a drag clamped to the span end, opening a tile at the edge)
  and cleared only by deliberate moves away — the observer's drift never touches it; the state's
  `isLive` is stored, not computed. `goLive` also **settles half a second inside the newest clip**
  (readout, footage check and shown frame agree — parked *at* `span.end` the half-open footage
  check reads "no footage" for the very frame on screen).
- **Playing out the live hour refetches it once — revising 0.3.13's "no second fetch".** Playback
  catching up with the newest footage now refetches the *same* window: new footage carries playback
  straight on (a de-facto live follow, ~segment latency, chip red); none stops it at the edge. The
  0.3.13 regression this guarded against — reload + rewind to the top of the hour, forever — stays
  pinned: the refetch seeks to the caught-up instant (no rewind) and a no-growth result stops
  playback (no loop), with a value-equal refetch skipping the player rebuild entirely so the
  picture doesn't blank. Pressing play while parked at the edge self-heals the same way: the player
  fires end-of-stream, the refetch finds what recorded meanwhile, playback continues.
- **A thrown track glides.** `ScrubFling` (pure, unit-tested) restates UIScrollView's `.normal`
  deceleration on a per-second base; the detail track's drag release runs it on a 16ms loop through
  the existing anchored-scrub path and settles with `endScrub` — so the window swap and the resume
  behavior fall out unchanged. A new grab cancels the glide but keeps the scrub open (resume intent
  survives); the span's edges stop a glide dead. The tab's scrubber already had ScrollView inertia.
- **One track language everywhere (`TimelineTrackStyle`).** The tab's histogram drew severity as
  bar *color* at a fixed 3pt width; the detail track drew green motion + a marker lane; the day bar
  drew alert ticks only. All three now share the detail's vocabulary: green motion bars at the
  **resolution of the data** (hairline-separated), review markers as red/orange **pills in their
  own lane**, `TimelineHatch` for no-footage (the tab hand-rolled an identical hatch — now the
  shared one), and the day bar ticks all severities. Each surface keeps its own axis conventions;
  it is the vocabulary that is unified, not the geometry. Rewriting the tab's gap bands also fixed
  the **vertical** axis drawing them 1pt tall (inverted coordinates — the vertical axis maps later
  instants to smaller offsets).
- **The stacked panel matches the mock.** The clock gained small trailing seconds (the tab's
  landscape readout shape; AM/PM dropped rather than trailing *after* the seconds), and the
  portrait transport is the mock's single row — cluster leading, speed + Live trailing, **small
  controls** (at regular size the row's minimum width overran the phone and silently pushed the
  whole layout past the screen edges — the first bug the new `detail-areas` highlight baseline
  caught), with a `ViewThatFits` two-row fallback for narrow split-view windows and large Dynamic
  Type.

An adversarial review pass (four dimension reviewers, two refuters per finding) reshaped several
of the above before landing, and the guards it forced are part of the contract:
- `advanceToNextWindow`'s post-refetch state writes are gated on **whether the load actually
  applied** (`load` now answers it) — a scrub or skip taken during the in-flight catch-up is newer
  intent, and the superseded refetch must neither re-mark the playhead live nor pause what the
  user resumed.
- `endScrub` is **scrub-generation guarded**: the settle can suspend on an hour fetch, and a new
  grab taken meanwhile owns the playhead — the older settle yields, and the resume intent
  survives to the settle that is actually last. `beginScrub` also invalidates in-flight window
  loads over loaded content (the drag owns the playhead; a landing load must not yank it) —
  deliberately not during the very first load, which must keep its right to resolve the spinner.
- The **glide is owned by the panel**, not the track: every playhead-moving verb runs through a
  coordinated actions wrapper that settles a running glide first (two drivers would fight over
  the playhead frame by frame), `beginScrub` cancels without settling so a caught glide's session
  carries its resume intent into the new grab, and the panel's `onDisappear` settles an abandoned
  glide. Both draggable strips also settle on **gesture cancellation** (a `@GestureState` reset is
  the only signal SwiftUI gives when `onEnded` never comes) so playback can't strand paused.
- `goLive`'s settle runs only over a `.ready` display — after a failed live-hour fetch the
  timeline still describes the old hour, and settling against it would teleport the readout.
- The tab histogram's **vertical gap bands really were still 1pt** in the first cut (the
  pre-existing `max(start + 1, …)` clamp ran before the reordering, collapsing it) — the band is
  now ordered before the minimum is enforced, which is the fix the earlier bullet describes.

## Timeline detail: the Hour-zoom preview filmstrip (0.5.3)
The mock's last deferred piece (out of scope in 0.5.0, explicitly spun off in 0.5.2): at Hour zoom
the scrub track fills with preview stills, one per slot of footage. Day/week zoom stay stills-free
— a cell there would be sub-cell-width noise, and each zoom flip would re-render every slot.

- **Slots live on a fixed ten-minute epoch grid** (`FilmstripSlots`, the `RecordingWindow`
  pattern): a slot keeps its identity — and its cached thumbnail — while the viewport slides
  around it, so scrubbing never re-renders a still. The grid is clipped to the span at both ends;
  at Hour density (480 pt/h) a slot is an 80pt cell.
- **Two materials, resolved per slot** (`RecordingFilmstripStore`): a completed hour renders
  through `AVAssetImageGenerator` over that hour's **authed** low-res `preview.mp4`
  (`makeAuthedAsset`, extracted from `makeAuthedPlayerItem`; ±30s tolerant seeks — the preview is
  ~1fps and a slot stands for ten minutes, so the nearest keyframe is indistinguishable and far
  cheaper). The live hour (no mp4 assembled yet) shows the nearest still preview frame **at or
  before** the slot — the same `mostRecent(atOrBefore:)` the tiles use, and the filter is also
  what keeps a historical gap slot from borrowing a *current*-hour still: every listed frame is
  newer than such a slot, so none qualifies.
- **Cached per (material, slot), regenerated only on material change.** The cache key is what the
  thumbnail was rendered from, so the one legitimate churn — the live hour completing into a clip
  — regenerates exactly those slots, and nothing else ever does. A failed render stays unresolved
  (retried by a later batch) rather than caching the failure.
- **Material is fetched once per span**, not per batch: scrubbing slides the slots inside a frozen
  span, so the clip/frame lists re-read only when the live edge extends it (the 30s overlay
  refresh cadence) — no fetch-per-drag-frame. A failed clips read keeps the last good material and
  leaves the span unmarked so the next update retries; frames stay best-effort on top (the tile's
  rule). The cache is bounded (144 slots ≈ a day); overflow evicts the slots farthest from the
  batch just requested.
- **The strip draws behind the track's canvas** so motion, markers, hatching and the pre-span wash
  stay legible over the stills, and the generation seam (`FilmstripThumbnailGenerating`) is
  internal — its fake lives in the owning test target, per the internal-seam rule. Cells are
  hairline-separated (the motion-bar separator), aspect-filled, on both axes via the now-shared
  `TrackGeometry`.
- **Snapshots capture the placeholder cells.** Network images can't render in a snapshot, so the
  store degrades to stable `.fill.tertiary` cells whenever material is missing — the new
  `detail-hour` baseline records that state across the matrix, and the six existing detail
  baselines are untouched because the strip is pixel-inert outside Hour zoom.
- The store rides `RecordingPlayerViewModel` (constructor-injected, built in the composition root
  with the Frigate preview provider + image loader), so thumbnails survive zoom flips and
  arrangement changes; the update trigger is a `.task` keyed on (slots, span) — a playhead tick
  that merely slides the cells re-requests nothing.

## Timelines open at Hour zoom; the live stream links to its camera's timeline (0.5.4)
Two small user-called improvements, one of them with an architectural edge worth recording.

- **Hour is the default density on both timelines.** The tab's scrubber opened at Day while the
  per-camera detail already opened at Hour (unchanged since 0.5.0) — so the two surfaces disagreed,
  and the tab's live edge, which is what a screen entry is about, arrived a few points wide. The
  tab's initial density is now the Hour preset; the pill and the pinch still reach Day and Week,
  and nothing else about the scale changes. This moves every Timeline-tab snapshot baseline (the
  histogram is drawn at 480 pt/h instead of 120), so those references must be re-recorded locally.
- **The live stream carries a Timeline button, and the Cameras vertical still does not depend on
  the Timeline one.** The destination is `RecordingPlayerView` — a Timeline screen — reached from a
  Cameras screen, which a direct `CamerasPresentation → TimelinePresentation` edge would buy at the
  cost of the first feature-to-feature *presentation* dependency in the package. Instead the grid
  takes the destination as an injected `@ViewBuilder` (`CameraGridView` is generic over it) and the
  composition root supplies it, exactly as it already supplies view-model factories: the link is
  wired where every other cross-feature wiring lives, and neither vertical learns about the other.
  The push is a `CameraTimelineRoute` value registered on the grid's stack, so the button sits in
  the detail's toolbar while the stack keeps owning navigation. It is offered even when a camera has
  no go2rtc stream — the recordings are there either way — and the instant is read as the push
  resolves, so the recordings open at the live edge rather than at whenever the view was built.

### The snapshot gate did not catch the Hour default — the area budget has a small-chrome blind spot
Recorded because it falsifies a claim the previous entry made in good faith. The 0.5.0 tolerance note
says `precision` (the **area** budget, 0.98) "is the real gate … a moved control, a wrong colour or
dropped text blows past ΔE 13 over far more than 2% of the frame". This change is a counterexample:
switching the tab's default density relabels the zoom pill (**Day → Hour**, the pill resizing with
the word) and redraws the histogram bars at 4× density, and **all four Timeline states passed on CI
against references that still depict "Day"**. 2% of an iPhone frame is ~59k pixels; the pill is ~11k
and the bars, being thin strips over a mostly-empty track, add roughly as much — about 1% together,
comfortably inside the budget.

The tolerance is **not** being changed here: tightening `precision` is what the glass drift already
spends `perceptualPrecision` on, and trading one for the other needs a local measurement pass, not a
guess. What changes is the rule of use — a green snapshot run means *nothing moved across a large
area*, not *the screen is unchanged*, so **baselines are re-recorded whenever a change alters what a
screen depicts, green run or not**. A stale reference is worse than a red one: it silently becomes
what every later diff is measured against, and the same budget then hides drift stacked on top of an
image that was already wrong. The Timeline-tab references are in exactly that state until they are
re-recorded locally against the Hour default.
