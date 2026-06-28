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
