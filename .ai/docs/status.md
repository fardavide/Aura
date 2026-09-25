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
  span end to the present (start fixed) and only fires when parked at the live
  edge and not scrubbing; a failed screen keeps retrying so a dropped connection self-recovers
  (see `decisions.md`). Since **0.3.3** the whole screen catches up immediately on re-entry and on
  returning from the background, the playhead parked at the live edge follows each extension, and
  tiles refresh their preview material **in place** on every extension — so scrubbing to the present
  shows current previews, not images frozen at first appearance.
  When the vertical size class is compact — iPhone landscape in practice (iPad keeps a regular height
  even in multitasking; macOS has no size class) — the layout splits side-by-side (v0.1.9) and hides the
  nav bar: a single-column scroll of camera tiles on the left, and a **full-height vertical** glass
  scrubber on the right that's kept visually identical to the bottom card (centered playhead, same
  histogram and zoom scale) except it reads top→bottom now→past, so scrolling **up** goes back in time
  (`ScrollableTimelineView` gained an `axis`). Everything else keeps the bottom card. See `decisions.md`
  — only the iPhone-landscape snapshot baselines change and need re-recording.
  Since **0.3.4** regular widths (iPad + macOS) size the tiles **best-fit to the window** (video
  wall, centered above the scrubber; minimum-width scrolling fallback), the scrubber zooms
  **continuously by pinch** (trackpad magnify on macOS) between the Week…Hour extremes with the
  playhead instant anchored across every zoom change (pill included), and placeholder tiles keep
  their 16:9 slot instead of collapsing to a bar — see `decisions.md`.
  Since **0.3.7** the camera tiles no longer get stuck on their loading spinner: the 30s live-edge
  refresh advanced the span and so **cancelled each tile's in-flight first load** (the load task was
  re-keyed off the whole span), stranding it. The first load is now keyed off the **fixed span start**
  with the live-edge follow on a **separate trigger** (`followLiveEdge`), and timeline reads carry a
  request timeout so an unresponsive server can't hang a load. See `decisions.md`.
  Since **0.3.9** the *screen* no longer gets stuck on its full-screen spinner either: the view model
  is now **`@State`-pinned** in `TimelineScreenView` (like Cameras/Events always were), so RootView's
  per-body-pass rebuilds can't swap the displayed screen for a never-loaded one whose `.task`s drive
  a discarded instance (permanent on macOS, spinner-flash + refetch per tab revisit on iOS), and the
  cameras `/api/config` read that gates first paint carries the same 15s timeout as the timeline
  reads. See `decisions.md`.

- **Pinch-to-zoom on the live view (v0.1.10).** Digital zoom + pan (1x–10x) on the live camera detail, both
  platforms: pinch (touch / trackpad magnify) zooms about the pinch point, drag pans with the
  content edges clamped to the viewport, double-tap toggles 1x↔2x at the tap point. The pinch
  anchor comes from `MagnifyGesture`'s start **location** (v0.2.3) — its `startAnchor` reports
  `.center` in practice, which pinned every pinch to the middle of the frame. A SwiftUI
  gesture container in `CommonPlayer` wraps the video; the clamped zoom/pan math is a pure value
  type unit-tested in the package. **Reworked in 0.3.5** to a **bare `AVPlayerLayer` host**: the
  video is the only thing inside the zoom container so it scales alone, the transport controls
  (play/pause, mute, PiP, LIVE) are a custom overlay **outside** the zoom (they no longer scale with
  the picture), and PiP is app-owned via `AVPictureInPictureController`. This replaced the earlier
  `AVPlayerViewController` host, whose bundled controls scaled with the video and whose built-in
  aspect-fit↔fill pinch couldn't be reliably suppressed — both bugs are gone by construction. See
  `decisions.md`. **0.3.6**: controls respect the safe area (the LIVE badge no longer tucks under
  the status bar) — the safe-area split lives in a shared `LiveVideoLayout`, now covered by a
  `CameraDetailSnapshotTests` screenshot test (control chrome over a black placeholder, no live
  player needed).

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
  **`TestDoubles`** target (product `AuraKitTestDoubles`). On macOS both Settings `Form`s now pin
  `.grouped` (the columnar default looked unpolished) and the Settings sheet reserves a minimum
  frame, so the drilled-in Camera Order list has room to actually show its cameras (v0.2.5 — the
  Mac-only gaps the iOS-only snapshot suite doesn't cover; see `decisions.md`).

- **Slice 7 — Cameras grid v2 restyle.** The camera grid + tiles were restyled to the "v2" design
  (`Cameras.dc.html`): dark 16:9 tiles with a LIVE marker, the name over a bottom scrim, a per-tile
  **activity badge** (alert = red / detection = amber, from in-progress `/api/review` items), an
  **offline** treatment when the still fails, and a **live·offline count** pill in the header. Layout
  is size-class driven (iPhone portrait = full-width list, landscape/iPad/macOS = grid). The live
  video detail (PiP + zoom) is unchanged. A new **camera-activity** vertical (`CameraActivity` +
  `GetCameraActivity` + `FrigateCameraActivityRepository`) reads `/api/review` and keeps the
  in-progress items. The grid **view model owns preview loading** (concurrent, so an offline camera
  can't block the rest) and tiles are pure — this removed an AttributeGraph churn / heap-corruption
  crash in the snapshot renderer (see `decisions.md`).
- **Cameras v2 finished (0.3.1).** The rest of `Cameras.dc.html` shipped: a **summary card** (RIGHT
  NOW active object, tap-to-open · TODAY event count + breakdown · RECORDING disk-free + days-kept) and
  **camera-group filter chips**. Three new Cameras-local reads — camera groups (`camera_groups`),
  today's event tally (`/api/events?after=`), recording storage (`/api/stats` + `record`) — each
  best-effort and load-time; the still refresh dropped to **2 s**. Endpoints were verified against
  Frigate v0.17.2 source and recorded in `/frigate-rest`. IR and the mock's tile drift stay dropped (no
  verified signal / the design is deliberately calm). Cameras grid snapshots: loaded / **activity** /
  **summary** / offline / empty / failed.
- **Animated nav icons (0.3.2).** The root `TabView` moved to the selection-value `Tab` API (typed
  tab enum) and each tab's icon plays an SF Symbol bounce when selected — see `decisions.md` for
  the per-tab trigger and the custom-tab-bar rejection.
- **Timeout hardening completed + shared `FrigateApiClient` (0.3.10).** Every Frigate read now
  carries the 15s bounded timeout (the remaining Cameras reads — groups, storage, activity,
  today-events, stills — and the whole Events data layer joined the Timeline/config reads of
  0.3.7/0.3.9), each pinned by a request-level test. The duplicated authed-GET + status→error
  ladder collapsed into `FrigateApiClient` in `CommonFrigate`; feature Data layers map its
  transport error into their own domain errors at the boundary. See `decisions.md`. The
  request-coalescing `/api/config` consolidation is still open (below).
- **Closed the two 0.3.9 exposures (0.3.11).** `/api/review` now takes a **required** `limit` (day
  timeline 1000, Cameras activity 100), so first paint no longer downloads an unbounded review
  payload on event-dense servers; and `UrlSessionHttpClient` builds its own session with a
  **600s `timeoutIntervalForResource`** wall-clock ceiling that the idle per-request timer couldn't
  provide (a byte-dribbling proxy no longer holds a load open forever). See `decisions.md`.
- **One shared, self-refreshing `/api/config` read (0.3.12).** Closes the standing consolidation
  follow-up: a `FrigateConfigProvider` actor holds the single config body, so a Cameras grid load
  costs **one** `/api/config` GET instead of three (the camera list, the group chips and the
  retention figures each decode their own slice of it). It is **reactive rather than cached** — a
  2-minute re-read pushes to subscribers, so chips and the summary card follow a server-side change
  while the grid is open, where they were previously load-time only. Request coalescing alone would
  have collapsed nothing (the three reads are sequential, never concurrent). The camera list still
  forces a fresh read so pull-to-refresh stays honest; the config stream carries failures so a first
  paint can't hang on an unreachable server, resolving to an empty slot on the first failure and
  leaving on-screen values alone on later ones. See `decisions.md`.

- **Timeline transport + full-resolution tiles (0.4.0).** The scrubber card carries the design's
  transport — skip ±10s, play/pause, 1× / 2× / 4× / 8× (the slim landscape card steps through the
  ladder with one button) — and playing swaps **every** tile from the low-res scrub material to that
  camera's own recording, reusing 0.3.13's window/mapping machinery. Playback is a *clock*: a
  `TimelineTransport` advances the one shared `ScrubClock`, tiles follow and correct their own drift,
  and the histogram scrolls under the fixed playhead (the scroll→clock direction is off while
  playing). Gaps are stepped over, the live edge stops playback, and play from the edge rewinds a
  minute — which closes the "resuming at the live edge" follow-up. Taking hold of the scrubber
  pauses. A tile whose hour holds nothing (or fails) stays on its previews and rejoins at the next
  hour with footage. **Reverses** the 0.3.13 "the grid keeps its previews" decision — see
  `decisions.md` and `.ai/plan/no-ticket_timeline-transport-fullres/`.

- **Slice 8 — Timeline detail, one camera on its own axis (0.5.0).** The screen a tile push opens
  was rebuilt to `Timeline Detail.dc.html`: the footage with a Liquid-Glass panel carrying a
  **24-hour day-overview bar** (hourly motion rollup, alert ticks, hatched gaps + future, the
  outlined slice the track is showing — drag it to jump), a **centre-anchored scrub track** (motion
  from the baseline, an alert/detection marker lane, hatched gaps, day dividers, a dashed live edge,
  a fixed playhead — drag it to scrub), a **ruler**, an Hour/Day/Week zoom, a day stepper, and a
  transport extended with **jump to previous / next activity** and a **Live** chip. The timeline
  reads are now **scoped to the camera** (`TimelineScope`; `cameras=` on review / motion / gaps).
  Three arrangements by size class: panel floating over the footage (phone upright), a **168pt
  vertical rail** (phone on its side, the mock's full-bleed layout), and the mock's hero-plus-wide-
  panel (iPad, macOS). The mock's **activity list, preview filmstrip and Save-frame / Clip-export
  are deliberately out of scope**, as are the `IR` badge and the discrete digital-zoom chip — see
  `decisions.md`.

- **Timeline detail polish batch (0.5.2).** The detail's footage now lives in a laid-out **top
  slot** the panel can never cover (portrait: video above the floating panel; landscape: beside the
  rail), is **pinch-zoomable** like the live view, and zoomed footage deliberately overflows the
  slot **under the glass**. Scrubbing any timeline (track, day bar, tab scrubber) **resumes the
  playback it paused**; the detail track got a **fling** (UIScrollView's deceleration curve, pure
  `ScrubFling`); the **Live chip stays red** while parked at/following the newest footage
  (`followsLiveEdge` intent, goLive settles onto the newest clip), and playing out the live hour
  **refetches the growing hour once** so playback follows fresh footage (revises 0.3.13's
  no-second-fetch rule — no rewind, no loop). All three timeline strips draw in one shared
  language (`TimelineTrackStyle`: data-resolution green bars, red/orange marker-lane pills, shared
  hatch); the panel clock gained trailing seconds and the portrait transport is the mock's single
  row. A `cameraAreaHighlights` env flag + `detail-areas` baseline outline the surface and the
  camera slot so panel-over-video regressions show up in snapshots. **Deferred**: the preview
  thumbnail filmstrip (landed in 0.5.3). See `decisions.md`.

- **Timeline detail: Hour-zoom preview filmstrip (0.5.3).** The mock's deferred filmstrip: at Hour
  zoom the scrub track fills with one preview still per **fixed ten-minute slot**
  (`FilmstripSlots`), drawn behind the canvas so motion/markers/hatch stay legible. Completed
  hours render via `AVAssetImageGenerator` over the **authed** per-hour `preview.mp4`
  (`makeAuthedAsset`, tolerant seeks); the live hour shows the nearest preview frame at or before
  the slot, upgrading when the hour completes into a clip. Thumbnails are cached per
  **(material, slot)** in `RecordingFilmstripStore` (bounded, farthest-from-batch eviction);
  material is fetched once per span so scrubbing costs no requests. Slots with nothing to show
  degrade to stable placeholder cells — which is exactly what the new `detail-hour` snapshot
  baseline captures. See `decisions.md`.

- **Hour default + live-stream → timeline link (0.5.4).** The Timeline tab's scrubber now opens at
  **Hour** zoom, matching the per-camera detail (which already did) — the live edge is readable on
  entry instead of a few points wide; the pill and the pinch still reach Day and Week. **The
  Timeline-tab baselines still depict the old "Day" pill and must be re-recorded locally — the
  snapshot job stayed green because the repainted area is under its 2% budget, so CI will not
  force this** (see the blind-spot note in `decisions.md`). And a camera's
  live stream gained a **Timeline** toolbar button opening that camera's recordings at the live
  edge. The Cameras vertical still doesn't depend on the Timeline one: `CameraGridView` is generic
  over an injected destination builder that the composition root fills with `RecordingPlayerView`,
  pushed as a `CameraTimelineRoute`. See `decisions.md`.

- **Timeline overlay reads made server-safe (0.5.1).** Field-reported outage: opening the Timeline
  froze a modest Frigate server (API unresponsive → web UI "offline", HA entity Unavailable, VOD
  playback starved). Root cause: Frigate 0.17's `/api/recordings/unavailable` runs an
  O(buckets × rows) scan **on the API event loop**, and we queried 7 days at ~2000 buckets — on
  open and every 30s (0.5.0's detail screen: ungated). Overlay reads now go out **one day-sized
  window at a time, sequentially, newest first** (`OverlayWindow` + `GetDayTimeline` as an
  `AsyncStream` of `DayTimelineSlice`s, merged by `DayTimeline.replacing`); a periodic refresh
  re-reads **only the stretch since the last one**; the detail screen's refresh is **gated at the
  live edge** like the tab's; the tab paints its grid before the overlays; and a walk cut short by
  an unreachable server resumes on a later refresh. See `decisions.md` and `frigate-integration.md`.

Package logic is covered by Swift Testing (489 tests as of 0.5.3). All four main screens — **Timeline**
(ready busy / gappy / quiet / **playing**, empty, failed), the **Timeline detail** (playing, paused
at 8×, week zoom, hour-zoom filmstrip, no footage, live, area highlights), the **Cameras grid**, the **Events list**, and
**Settings** (each across its loaded/empty/failed or first-run/saved/error states, plus a
Camera Order populated/empty pair and a menu state whose camera count read fails) — are covered
by **screenshot tests** (app-hosted `AuraTests`, `swift-snapshot-testing`, test-only) across
iPhone + iPad (portrait + landscape) × light + dark on the simulator.
Reference PNGs are committed beside the tests. macOS is excluded (AppKit offscreen rendering can't
capture glass faithfully — see `decisions.md`). The detail screens (live camera, event clip) are
not snapshot-tested — they center on video players that can't render in a snapshot.
- **Slice 11 — app icon + picker (0.5.6).** The shipped icon is a lit ring (halo) instead of a stock
  camera glyph, with a drawn dark-appearance variant and drawn — not downsampled — small macOS sizes.
  Settings › Appearance › App Icon offers six alternates (Heavy, Thin, Sweep, Aurora, Signal,
  Daylight), all treatments of the same ring. The system owns the current choice; nothing is stored
  beside it. iOS-only: the row is absent on macOS, via an optional factory rather than `#if os`.
  **Verified in the simulator — picker switches the icon and the Home Screen follows.**
- **App shell + Settings: Aurora restyle (0.6.0).** The Settings sheet is now flush to the bottom
  (r30 top corners, grabber, gradient rim), painted on the `CommonDesign` sheet colour with its own
  head washes and glow; the menu's rows gained live summaries — Server shows `host:port` (or "Not
  configured"), Camera Order shows the current enabled-camera count (omitted, not dashed, while
  unknown or on a failed read), App Icon shows the current icon's artwork and name. The Theme picker
  is `AuroraSegmentedControl` in its recessed-well container; Done is disabled with a stated reason
  before a server exists; the sheet now reloads the root on every dismissal (Done or swipe), so a
  theme picked and then swiped away still applies. `ServerSettingsView`'s Save moved to a pinned
  bottom gradient button so it survives the keyboard in compact height; `CameraOrderView` gained a
  "no cameras" empty state. The tab bar itself is untouched system chrome — its active colour comes
  entirely from the now-filled `AccentColor` asset (pink pair), which is also the app's one link
  colour.
- **Cameras tab: Aurora restyle (0.6.0).** The summary card and the live-count pill are gone,
  replaced by a chip row (activity, today's tally, storage, and an offline count when non-zero)
  above the existing group-chip row. The wall is a custom `CameraWallLayout`: on iPhone portrait the
  hero sits full-width above a 2-column grid, on iPad/macOS it spans 2fr on the left beside a 1fr
  side column, and iPhone landscape keeps its plain 3-up grid with no hero at all. The hero is
  whichever visible camera has the most recently started **alert** (never a mere detection), so the
  2s activity refresh can't reshuffle the wall; the swap animates. Every tile lives in one `ForEach`
  behind the layout so a hero swap never rebuilds a tile's decoded still. The header chips are now
  narrowed to the selected group's cameras, so a group with nothing visible shows neither a stale
  activity chip nor a wrong offline count.
- **Timeline tab + Timeline detail: Aurora restyle (0.6.0).** Both screens keep their settled
  behaviours (the tab's scrolling 7-day strip with pinch zoom; the detail's Hour/Day/Week scrub
  track) and take the new paint: `TimelineTrackStyle`/`TimelineHatch` now delegate their colours to
  `CommonDesign`'s `AuroraTrack` (intensity-coloured motion bars, gradient playhead, dark well,
  hatched gaps/future), so both screens share one track vocabulary. The tab gains a hero tile (the
  camera with the current alert, else the first) living in one `ForEach` via `HeroGridLayout` so a
  hero swap reorders instead of rebuilding a tile; iPad takes a fixed 3-column grid, macOS keeps
  `TimelineGridLayout.bestFit`. Both sheets are flush-bottom (the tab's has no grabber — it isn't
  dismissable by drag); the detail sheet's zoom picker is `AuroraSegmentedControl` with the full
  brand gradient on its selected segment. `ReviewMarker` gained `camera`/`label` fields.
- **Events tab: Aurora restyle + real alert severity (0.6.0).** Severity is no longer guessed — an
  Events-local `/api/review` read is joined against `/api/events` by id (an event is an alert when
  an alert-severity review item lists it in `data.detections`), giving the ALERT tag, the gradient
  thumbnail ring, and a "Latest Alert" hero card real meaning (falls back to "Latest Event" with no
  alert today). Label filter chips, hour groups with a hairline + count, and glass rows replace the
  previous flat list; a new detail-screen header replaces the old title bar.
- **Live camera screen: Aurora restyle (0.6.0).** The video sits in a 16:9 gradient-framed card
  with a soft violet glow behind it, the LIVE pill moved inside the card's top-left corner, and the
  transport controls are a floating glass pill below the card — `LiveVideoArrangement` (`.card` /
  `.fill`) makes the compact-height (landscape) full-bleed layout and the regular-height framed-card
  layout two cases of one pure rule, unit-tested independently of the view.
- **All six Aurora slices land together as one restyle** (`CommonDesign` token target, Timeline tab,
  Timeline detail, app shell/Settings, Cameras, Events, Live) — 642 AuraKit tests, every snapshot
  suite re-recorded on the iPhone 17 Pro simulator (iPhone + iPad × portrait/landscape × light/dark).
  Verified iOS Simulator and macOS builds both green.
- **Zoom chrome + grow-past-the-frame pinch-zoom, Live and Timeline detail (0.6.1–0.6.6).** One
  shared curve (`AuroraZoomChrome`) fades the border out and blurs the picture as a pinch begins,
  clearing back to sharp near fill scale — same on both screens. The zoomed picture grows unbound
  past its own rest-state card (Live's `.card`, Timeline detail's `.stacked`/`.split` via
  `growingAboveThePanel`) rather than staying boxed inside it, all the way to the true screen edges
  behind the nav bar and the floating controls/panel (`.rail` still clips at its own box, deliberately
  deferred). `ZoomableContainer` gained `alignment`/`restOffset`/`contentSize` parameters to support
  this: a rest-state card smaller than, and positioned within, a bigger growable canvas. See
  `decisions.md`'s 0.6.2–0.6.6 entries for the several real bugs this surfaced (mask/backdrop corner
  rounding, panel-height measurement, a `.padding()` silently shrinking the growth canvas, and —
  found only after two rounds of on-device testing — every pinch's anchor/pan/clamp math being
  computed against the whole container instead of the actual (smaller) content it was measuring).
- **Alert-led ordering is now the user's choice, and the Timeline grid animates it (0.6.8).** A
  "Follow Activity" switch in Settings → Cameras governs both walls at once: on (the shipped
  default, so nothing changes for anyone who ignores it) the newest alert's camera takes the large
  tile; off, both grids stay in the saved Camera Order whatever the alerts do. Alert badges are
  untouched by it — the preference decides *position*, not what the screen reports. The Timeline
  grid's hero flip was unanimated and snapped; it now travels on the same shared curve the Cameras
  wall already used.
- **Events pages backwards through history (0.6.9).** The tab used to stop dead at its first 100
  events. Scrolling to the end of the list now fetches the next page with Frigate's `before` cursor
  and appends it, repeating until the server has nothing older. Loaded content is never blanked to
  page: a failed page costs only the footer, which offers a retry.
- **Detection feedback on the event screen (0.6.10).** On a server with Frigate+ enabled, an event
  detail asks "Is this a dog?" and sends the answer — confirm (`POST …/plus`) or false positive
  (`PUT …/false_positive`). Suggesting the *right* label is impossible: the API annotates with the
  event's own label and takes no corrected one, so the panel links to plus.frigate.video where the
  relabelling actually happens (see `decisions.md`). Hidden entirely unless the server reports the
  add-on and the event is submittable. First write path in the app — `FrigateApiClient` gained
  `post`/`put`.
- **A reported detection stays reported, and says so (0.6.11).** 0.6.10 judged "already reported"
  from the list's stale copy, so leaving and re-opening an event offered a second report that the
  server then refused. The detail screen now re-reads the event (`GET /api/events/{id}`) on open —
  no local store, and it picks up verdicts given in Frigate's web UI or on another device. A
  detection reported wrong reads struck through with a "NOT A DOG" badge in the list and on the
  event screen. The reporting panel moved to the bottom edge, clip centred above it.
- **The "NOT A …" badge is gone (0.6.12).** It shipped alongside the strikethrough and mangled the
  row on a real deployment: the badge text scales with the label, so `motorcycle` wrapped the label,
  the severity tag and the badge each mid-word. A reported detection now reads struck through in
  muted grey and nothing else; the event screen's panel still says it in full. Snapshot fixtures
  carry the longest realistic label now, which is what eight green baselines had been missing.
- **The ink alone still wasn't enough, twice over (0.6.13–0.6.14).** `TextTertiary` barely dimmed;
  the fix to `TextMuted` still didn't read as "wrong" at a glance while scanning. Four treatments
  were rendered side by side as a throwaway comparison and shown to the user before choosing: a
  small fixed-width `xmark.circle.fill` in front of the label is what actually breaks the scan
  pattern — in the list, the hero card, and the event screen. The row's `minimumScaleFactor`
  tightened to `0.6` to keep "Motorcycle" on one line with the icon added to its width budget.
- **Timeline detail live and scrub playback are split by media purpose (0.6.15).** Live now uses the
  camera's authenticated go2rtc HLS source rather than querying the recording VOD at its half-open end, and
  returning to history restores VOD playback. During a drag, the video uses the main Timeline tab's
  low-resolution `preview.mp4` / live-hour WebP material; the full-resolution VOD is sought only
  when the scrub settles. Covered by 728 passing AuraKit tests, the complete recording-detail
  snapshot suite, and green iOS Simulator + macOS builds.
- **Verified detections now carry a check (0.6.16).** A correct Frigate+ verdict displays a
  small blue `checkmark.circle.fill` before the label in the list row, hero card and event detail;
  an incorrect verdict keeps its muted X, muted label and strikethrough. The verdict-to-symbol
  mapping has a focused unit test, with dedicated verified-list snapshots and updated submitted-
  detail references covering the settled UI across phone/tablet layouts and both themes. Full
  verification: 729 passing AuraKit tests, the focused list/detail snapshot suites, and green iOS
  Simulator + macOS builds.

- **Slice 12 — Exports (0.7.0).** A fourth `Exports` tab over a new `Exports` vertical
  (Domain/Data/Presentation), built to the approved design. The server's clip library, newest first
  and grouped by day: card variants for ready, no-thumbnail, processing, downloading and
  download-failed; first-class loading, empty, unreachable, retrying and refresh-failed-over-content
  states; a pushed player with its own transport; and a copy handed to the platform's destination UI
  (iOS share sheet / macOS save panel) via a new `CommonFiles` wrapper. Transfers live in an
  app-scoped `DownloadCenter` so they survive leaving the tab, driven by a new streaming
  `HttpDownloadClient` seam in `CommonNetwork`. Wider-than-tall canvases put the clip beside the
  library instead of pushing it. The verified `/api/exports` contract was added to `/frigate-rest`,
  which had no exports section at all. **790 AuraKit tests + 62 app tests green, iOS and macOS
  builds green, 64 new snapshot baselines.** See `decisions.md` for the duration, path-validation,
  progress-ownership and empty-copy calls, and for what was deliberately left out.

- **Slice 13 — the export range selector (0.7.1).** Issue #57, built to the Claude Design return
  for #60. Export mode transforms the scrub track already on screen: two handles, the region
  between them held at full strength while everything outside recedes, a readout of exact start,
  end and duration, and the transport replaced by Cancel / Play selection / Create Export and then
  by a lifecycle strip. Seeded at playhead −0:30/+1:00, whole seconds throughout because Frigate
  truncates export bounds to integers. The range maths — seeding, clamping, non-crossing, the
  one-second minimum, whole-second quantisation and "does this hold any footage" — is a pure
  `ExportSelection` in Timeline Domain; creation and its failure classification are `CreateExport`
  and `ExportsError.isRetryable` in Exports Domain, injected as use cases. **The zoom ladder gained
  a permanent fourth rung, `Minute` at 3 600 pt/hour** — at Hour the seed is twelve points wide, so
  nothing else on the screen could be designed until that was fixed; Davide confirmed it before the
  UI was built, and every `RecordingPlayerSnapshotTests` baseline was re-recorded for it.
  **862 AuraKit tests green, iOS Simulator build green.** See `decisions.md` for the rung, the
  outside-the-clip dim, the knobs-outside rule and why a rejection removes its retry control.

- **Local + remote server addresses (0.7.2).** The connection now holds a required remote address
  and an optional local one, and the app picks between them on its own: no local address or no
  Wi-Fi → remote with no wait at all; on Wi-Fi → one 600 ms `/api/version` probe of the local
  address, remote the moment it doesn't answer. Two interface-pinned `NWPathMonitor`s (not the
  default path, which runs over `utun` with Tailscale up) re-point the whole app when the network
  changes, and only a genuine change rebuilds the tree. The composition root is built from a
  resolved `ActiveServer`, so nothing below it knows there are two. The Settings row tags the
  address in use. **902 AuraKit tests + the app suite green, iOS Simulator and macOS builds green;
  never run against a real second address** (see Next). See `decisions.md`.

- **Chips are visible on light-mode cards again (0.7.3).** Reported against the clip editor, found
  on four screens: a chip's fill and its border were both white in light mode, so over an elevated
  surface — a card, a sheet, the timeline panel — the control collapsed to a bare glyph with no
  edge. The border is now ink and the fill stayed white, which fixes every site without touching
  one, keeps the chips over the aurora background looking exactly as they did, and leaves dark mode
  byte-identical. A contrast assertion in both schemes guards it, because a 1 pt rim is far below
  the screenshot suite's area tolerance and would have stayed green while depicting the bug; all
  284 light references were re-recorded deliberately. See `decisions.md`.

- **The video card exists only while there is a picture in it (0.7.4).** A TestFlight screenshot
  showed the Timeline detail's hero as a square-cornered black slab over a gap. Built to
  `Timeline Detail - Empty States.dc.html` (option 1c): over a gap, while loading and with the
  server unreachable the rim, glow, letterbox, camera chip and LIVE pill go with the picture in one
  200 ms crossfade, and a message sits in the rest rect on the aurora — the failed one being the
  stack Live already draws. `RecordingDetailState` carries a four-case `slot` in place of the
  footage flag, derived by the view model (a drag's preview picture counts as footage). Timeline
  tiles clear their well and keep their outline; the hero tile drops rim and glow at the same
  footprint. Pinned by seven view-model tests; the detail's no-footage/failed and the Timeline
  tab's placeholder-tile baselines re-recorded. See `decisions.md` for the three open questions
  decided there, including the stacked card width left as is.

## Next
- **Verify the two-address switching on the real network (0.7.2).** Every path is unit-tested
  against fakes, but no probe has ever been sent to a live Frigate. Confirm on the running
  deployment: at home on Wi-Fi the Settings row tags **LOCAL** and the grid loads over the LAN
  address; on cellular it tags **REMOTE**; walking out of the house re-points the app without a
  relaunch; on a foreign Wi-Fi the delay before the first screen is not perceptible; and that iOS's
  **Local Network** permission prompt appears and, once granted, the local probe succeeds (the
  usage description is already in `Config/Aura-Info.plist`; a denied prompt silently means the app
  always falls back to remote).
- **Verify the range selector against a real Frigate server, and on a device.** Nothing in slice 13
  has touched a live instance: `POST /api/export/{camera}/start/{s}/end/{e}` is built to the
  verified v0.17.2 contract but never sent, and the create → processing → ready path has only been
  exercised against a fake. Issue #57 also requires the control's effect to be manually verified on
  iOS Simulator/device and macOS before it closes.
- **The design's seven remaining open questions** (its §10) are unanswered — the rung label
  (`Minute` vs `Min` by arrangement, currently implemented as drawn), the grab bar, withdrawing the
  day stepper at AX4, the white-on-gradient contrast of the shipped primary button, the `CLIP MODE`
  badge on the rail, and whether Play selection should loop.
- **Press-and-hold precision (issue #58) is not built.** The design specifies it fully and the base
  release is built so it is a density change rather than a value change, but nothing of it ships.
- **Finish the Mac's share of the Exports design (0.7.0).** The sidebar
  (`.tabViewStyle(.sidebarAdaptable)`), the separate player window (`openWindow(value:)`), the
  `⌘R` / `⌘S` / `⌘.` key equivalents and the right-click "Show in Timeline" action are all
  specified and none are built — each is an app-shell or scene change rather than an Exports-local
  one.
- **Make export downloads survive app suspension.** The transfer is a delegate-driven download task
  on an ordinary `URLSession`, so it survives navigation but dies with the app; the design calls for
  a background session, which needs `.background(withIdentifier:)` plus app-delegate completion
  plumbing.
- **Verify Exports against the real server.** Every path is unit-tested against the v0.17.2
  contract but nothing has touched a live instance. Confirm on the running server: `/api/exports`
  decodes (especially `date` arriving as a number); the media URL really is `<base>/exports/…`
  behind whatever proxy is in front of Frigate; authenticated mp4 playback works in `AVPlayer`; and
  a real multi-megabyte download reports progress and hands off to the share sheet.
- **Verify detection feedback against the real server (0.6.10).** Every path is unit-tested against
  the v0.17.2 contract, but no verdict has ever been sent to a live Frigate+ instance. Confirm on
  the running server: the panel appears at all (i.e. `/api/config` really carries `plus.enabled`);
  a confirm and a false positive both return 200 and show up in the Frigate+ dataset; and that the
  admin-role requirement on port 8971 doesn't reject the app's Basic-auth credentials.
- **Verify the tab-icon bounce on device** — whether the iOS 26 / macOS 26 system tab bars honor a
  symbol effect inside a custom `Tab` label is unconfirmed (see `decisions.md`); if stripped, the
  icons just stay static.
- **Cameras v2 — verify on the real server.** The summary card + chips were built against Frigate
  **v0.17.2 source** (not a live server): confirm on the running instance that `camera_groups` parses
  (both array + comma-string membership), `/api/stats` exposes the `/media/frigate/recordings` mount,
  and the `record.*` retention max reads sensibly. Also sanity-check the **2 s** still refresh against
  real `latest.jpg` load times / bandwidth.
- **Xcode Cloud workflow (App Store Connect, manual)**: **remove the two test actions** (iOS +
  macOS), keep the archives. Verified 2026-07-07: even the package-owned `AuraKitTests` scheme
  hits the app-container limitation on Xcode Cloud — both test actions fail with "1 error,
  0 test failures" before any test runs (see `decisions.md`). All testing is carried by the
  PR gate on `main`, so archives only ever see verified commits.
- **Verify full-res recordings playback on the real server (0.3.13).** The single-cam player is
  built and unit-tested, but AVPlayer against Frigate's VOD HLS has still never been run — the web
  UI uses hls.js on every platform, never native. Confirm on the running instance: the
  `/vod/{camera}/start/{s}/end/{e}/master.m3u8` playlist loads at all; a seek lands on the instant
  the clock claims (this is the wall-clock ↔ player-time mapping); 4×/8× hold up on real camera
  bitrates; and, if the server is behind a Basic-auth proxy, that HLS **segment** requests carry the
  auth header (headers are not guaranteed to reach sub-requests — port 5000 is unaffected).
- **Verify the Timeline transport on the real server (0.4.0)** — playing opens **one full-res HLS
  stream per camera at once**, which no test can exercise. Check on the running instance: total
  bitrate at the real camera count (this is the first thing expected to hurt); whether 4×/8×
  actually plays smoothly or degrades to stepping (nginx-vod-module isn't known to publish
  I-frame-only playlists); whether tiles stay close enough to each other to read as synchronised;
  and that the hour swap mid-playback doesn't stall every tile at once.
- **TestFlight: verify Timeline detail's media handoff on the real server.** At the live edge,
  confirm the go2rtc HLS picture replaces the recording rather than showing a no-footage overlay; during a long
  drag, confirm the low-resolution preview keeps pace; on release or a skip backward, confirm the
  full-resolution VOD resumes at the displayed instant.
- **Timeline follow-ups**: auto-load ranges older than the current ~7-day span as you scroll; the
  `camera=all` batch clip-list optimization; richer markers. (The tile live-follow gap — frames
  fetched once per tile on appear — was closed in 0.3.3: tiles refresh their material in place on
  every span extension.)
- A real **app icon** (current is a placeholder; the mac slots are `sips` downscales of the
  1024px source — regenerate them with the new artwork, and keep them filled: empty mac slots
  ship no macOS icon at all, see the App Store packaging decision).
- A **stream picker** when a camera exposes multiple go2rtc sources. (**PiP keep-alive** across
  navigation was implemented in 0.3.5 via a session retainer — needs the on-device check below.)
- **Verify the reworked live player on device (0.3.5)** — the bare-`AVPlayerLayer` host can't be
  covered by the package or snapshot tests. Confirm: pinch zooms only the video (controls stay put);
  no stray aspect-fill pinch; PiP starts from the button and **survives navigating away**; auto-PiP
  on backgrounding still hands back cleanly; the audio-interruption live-edge recovery still works.
- **Verify the return-from-background recovery on device (0.5.5)** — the reported frozen picture is
  fixed by a scene-phase rebuild whose *paths* are unit-tested, but the failure it repairs only
  happens on a real device. Confirm all three: leave and re-enter the app with the live view open;
  the same with auto-PiP engaging (the hand-back must not double-reload or drop the picture); and
  paused-across-a-background, where the next play must come back live.
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
