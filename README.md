# Aura

A native **iOS + macOS** SwiftUI client for [Frigate NVR](https://frigate.video) — a personal,
single-user companion app and portfolio piece.

## Features

- **Cameras** — live grid of all cameras, with a user-defined order; tap a tile for fullscreen
  live playback (go2rtc HLS via AVFoundation) with Picture-in-Picture on iOS and pinch-to-zoom + pan.
- **Timeline** — a synced multi-camera scrub view: preview tiles over a single continuous
  scrollable timeline with an activity histogram (Liquid Glass), Hour/Day/Week zoom, and a
  30-second live-edge auto-refresh. Play/pause and 1–8× run every camera's full-resolution
  recording forward together. Tap a tile for **that camera on its own time axis**: a day-overview
  bar, a scrubbable activity track with a fixed centre playhead, Hour/Day/Week zoom, and a transport
  that jumps between activity. iPhone landscape gets a dedicated side-by-side layout throughout.
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

### 0.6.1 — 2026-09-06
- **Timeline's sheet sits flush behind the tab bar**, matching every other panel, instead of
  floating with a gap above it.
- **Pinch-to-zoom no longer breaks** after swiping back from Timeline detail.
- **Pinch-to-zoom now looks identical on the Live and Timeline-detail screens** — both start with
  the same gradient-rimmed frame, glow softly behind it as you zoom in, then let the frame and glow
  fade away together as the picture fills the screen.
- **Fixed a stray line** that could show across the Settings sheet.
- **The three tabs' titles now look and behave the same** — left-aligned with a subtitle, and the
  content scrolls behind a soft glass backing as you scroll, on Cameras and Events too.

### 0.6.0 — 2026-09-06
- **A new look: Aurora.** A blue→violet→pink gradient runs through every screen — under the
  glass sheets and panels, on the selected segment, on alert badges and the primary action.
  The tab bar is now a neutral floating system bar with a coloured active icon; sheets (Timeline,
  Timeline detail, Settings) sit flush to the bottom, rounded only on top.
- **Cameras gets a hero.** Whichever camera has the current alert (or the first camera, if none
  does) is shown large at the top, with a chip row for today's activity, storage and offline
  count — replacing the old summary card.
- **Events shows its alerts.** A "Latest Alert" card leads the list, rows carry an ALERT tag when
  Frigate flags them as one, and label chips filter the list — all read from Frigate's own
  alert/detection classification.
- **Live and Timeline detail get a framed video card** with the gradient rim and a floating glass
  control pill, and Timeline's histogram now colours motion by intensity with a gradient playhead.
- **Settings rows show what they lead to** — the server host, the camera count, the app icon
  preview — before you tap in.
- Bundles the Urbanist typeface (SIL Open Font License) for headings and titles.

### 0.5.6 — 2026-08-09
- **A new app icon, and six more to pick from.** Aura's icon is a lit ring instead of a stock
  camera glyph, and Settings › Appearance › App Icon offers six alternates — Heavy, Thin, Sweep,
  Aurora, Signal and Daylight — that change the Home Screen icon as soon as you tap one. iOS
  shows its own confirmation when the icon changes; that alert comes from the system, not Aura.
  The row is absent on macOS, which has no swappable icon.
- **The icon has a real dark version.** Previously the system guessed one from the light artwork;
  now there is a proper dark-mode icon, and the small macOS sizes are drawn rather than shrunk,
  so the ring stays readable at 16 points.

### 0.5.5 — 2026-08-03
- **A live stream comes back when you do.** Returning to Aura with a camera's live view open used
  to leave a frozen picture that only playing again fixed by going back to Cameras and reopening
  the stream. The view now picks the stream back up at the live edge — including when it hands
  back from a Picture-in-Picture window, and when you had paused it, on the next play. Merely
  switching windows or dismissing a banner still leaves playback untouched.

### 0.5.4 — 2026-07-31
- **Timelines open on the hour.** The Timeline tab's scrubber now starts at Hour zoom, like a
  camera's own timeline does — the last stretch of footage is readable the moment the screen opens,
  instead of squeezed into a few points at Day zoom. The pill and pinch still reach Day and Week.
- **Jump from a camera to its recordings.** A camera's live stream has a Timeline button in the
  title bar that opens that camera's timeline at the live edge, so you can rewind what you are
  watching without going through the Timeline tab and finding the camera again.

### 0.5.3 — 2026-07-29
- **The camera timeline shows what happened.** At Hour zoom, the scrub track fills with a
  filmstrip of preview thumbnails — one still for every ten minutes of footage — so you can see
  what an hour holds before scrubbing to it. Completed hours draw their stills from the recorded
  previews; the in-progress hour uses its freshest preview frame, upgrading once the hour's
  preview is assembled. Stretches with nothing recorded stay as empty cells.

### 0.5.2 — 2026-07-29
- **A camera's timeline puts the picture first.** On iPhone the footage now sits at the top of the
  screen, fully visible above the controls, instead of centred and half-hidden behind them — and
  the same in landscape, beside the side rail.
- **The recording is zoomable.** Pinch, drag and double-tap on a camera's timeline work just like
  the live view — and zoomed footage slides *under* the glass controls instead of stopping at an
  invisible edge.
- **Scrubbing hands playback back.** If the recording was playing when you grabbed a timeline —
  the track, the day bar, or the Timeline tab's scrubber — it resumes when you let go.
- **Throw the timeline.** Releasing the camera timeline with speed keeps it gliding and eases it
  to a stop, like a scroll view.
- **Live stays red.** The Live chip no longer flicks back to grey seconds after tapping it — the
  recording parks on the newest footage and reads as live until you deliberately move away. And
  when playback catches up with the newest footage, it now picks up whatever was recorded in the
  meantime and keeps going.
- **Every timeline speaks one design.** The Timeline tab's scrubber, the camera timeline's track
  and its 24-hour day bar now share the same look: green activity bars at the data's resolution,
  red/orange event markers in their own lane, hatched no-footage stretches. The day bar also marks
  detections now, not just alerts.
- The timeline panel's clock shows seconds, and the portrait controls sit on a single row, as
  designed.

### 0.5.1 — 2026-07-28
- **The Timeline no longer overwhelms the server.** Opening the Timeline (or a camera's own
  timeline) used to ask Frigate for a whole week of activity in one query, and re-ask every half
  minute — on a modest machine that could freeze Frigate's API for tens of seconds, long enough to
  show it offline and drop it from Home Assistant. Activity now loads one day at a time, newest
  first, and each periodic refresh re-reads only the seconds since the last one.
- While browsing history on a camera's timeline, the periodic refresh now pauses entirely — same
  as the Timeline tab — and resumes at the live edge.
- The camera grid on the Timeline tab now appears as soon as the cameras are known, with the
  activity strip filling in behind it, so an unreachable activity endpoint no longer blanks the
  screen.

### 0.5.0 — 2026-07-28
- **One camera, one time axis.** Tapping a camera in the Timeline now opens a proper timeline of its
  own: the footage with a Liquid-Glass panel against it carrying a 24-hour overview of the day, a
  scrubbable activity track with the playhead fixed at the centre, and a ruler under it.
- The track shows **that camera's** activity rather than the whole system's — motion rising from the
  baseline, alerts and detections in a lane above it, stretches with nothing recorded hatched, a
  divider at each midnight and a dashed line at the live edge.
- **Drag the track to scrub**, or drag the day bar to jump to any time of day. Step a whole day
  either way with the arrows beside the date, and switch the track between Hour, Day and Week.
- The transport gained **jump to the previous / next activity** and a **Live** chip that goes red
  once you are parked at the newest footage.
- Scrubbing into a stretch with no recording says so on the picture instead of leaving the last
  frame up, and the readout keeps the time you actually asked for.
- Adapts per device: the panel floats over the footage on a phone held upright, becomes a rail down
  the side when you turn it, and spreads out beside the picture on iPad and Mac.

### 0.4.0 — 2026-07-27
- **The Timeline plays.** The scrubber card now carries a transport — play/pause, ten seconds
  either way, and a 1× / 2× / 4× / 8× speed selector — so the whole grid runs forward together
  instead of only moving when you drag it.
- **Every camera plays its real recording, not the low-resolution scrub preview.** Press play and
  each tile switches to the footage itself, carrying on from one hour into the next; pause, and the
  tiles go back to the previews that make scrubbing instant.
- Playback steps over stretches with nothing recorded rather than sitting on a frozen frame, and
  stops when it catches up with the present. Pressing play while parked at the live edge backs up a
  minute so there is something to watch.
- Taking hold of the scrubber hands the playhead back to you — playback pauses instead of fighting
  the drag.
- A camera whose hour holds no footage (or that the server can't serve) stays on its preview
  material rather than going blank, and rejoins full resolution at the next hour that has footage.

### 0.3.13 — 2026-07-27
- **Tap a camera on the Timeline to watch its recording at full resolution.** Until now the
  timeline could only be scrubbed through low-resolution previews; the new player streams the
  recorded footage itself, opening at whatever moment the scrubber was parked on.
- The player has the transport you'd expect from the Frigate web client: **play/pause, skip back
  and forward ten seconds, and a 1× / 2× / 4× / 8× speed selector.** Playback rolls straight on
  from one hour into the next, and stops when it catches up with the present.
- Stretches with nothing recorded are called out rather than silently skipped past — the clock
  keeps showing the real time of the frame on screen even where footage is missing.

### 0.3.12 — 2026-07-27
- The camera grid asks the server for its configuration **once** per load instead of three times —
  the camera list, the group chips and the recording figures now share a single read, so the screen
  opens with noticeably less work on the server.
- The chips and the summary card now **keep themselves current**: they re-read every couple of
  minutes while the grid is open, so a group or retention change made on the server shows up
  without reopening the app. A failed re-read quietly leaves what's on screen alone.

### 0.3.11 — 2026-07-23
- Timeline first paint no longer downloads an unbounded activity list on busy servers: the review
  markers behind the day timeline are now capped, so a camera setup with heavy history opens fast.
- A stalled connection that keeps trickling bytes can no longer hold a screen loading forever —
  every server transfer now has a 10-minute ceiling on top of the existing 15-second idle timeout,
  generous enough never to interrupt a legitimate slow download.

### 0.3.10 — 2026-07-23
- Every server read now gives up after 15 seconds instead of hanging for up to a minute on an
  unresponsive server: the camera grid's groups, storage and activity info, today's event tally,
  camera stills, the events list, and event thumbnails/clips — completing the timeout hardening
  the timeline got in 0.3.7/0.3.9.

### 0.3.9 — 2026-07-23
- Timeline: fixed the screen getting stuck on its full-screen loading spinner — switching tabs
  could silently swap in a fresh, never-loaded screen that nothing would ever load (on the Mac
  this could hit on every visit). The Timeline now keeps the same loaded screen alive across tab
  switches, like Cameras and Events always did, and the camera-list fetch that gates it now times
  out instead of hanging on an unresponsive server.

### 0.3.8 — 2026-07-23
- Live camera: pinch-to-zoom now reaches **10×** (up from 4×), so you can push in much further to
  read faces, plates, or distant detail. Panning, the double-tap toggle, and the controls staying
  put are all unchanged.

### 0.3.7 — 2026-07-23
- Timeline: fixed the camera tiles getting stuck on their loading spinner and never showing footage
  — the periodic live-edge refresh was cancelling each tile's first load before it could finish. The
  first load now always runs to completion, and the timeline no longer waits forever on an
  unresponsive server.

### 0.3.6 — 2026-07-23
- Live camera: the LIVE badge and playback controls no longer tuck under the status bar / notch —
  they now sit within the safe area while the video still fills the screen edge to edge.

### 0.3.5 — 2026-07-22
- Live camera: pinch-to-zoom now scales **only the video** — the play, mute, and Picture-in-Picture
  controls stay put at their normal size instead of zooming along with the picture.
- Live camera: fixed the pinch occasionally snapping to a "zoom to fill" you couldn't pan back out
  of — that stray behavior is gone for good.
- Live camera: refreshed on-glass controls (play/pause, mute, Picture-in-Picture, a LIVE badge)
  that fade out on their own and come back with a tap.

### 0.3.4 — 2026-07-21
- Timeline: on Mac and iPad the camera tiles now size themselves to the window — a few cameras
  fill the screen like a video wall instead of huddling in a corner at thumbnail size.
- Timeline: pinch to zoom the scrubber — trackpad pinch on Mac, two fingers on iPhone/iPad —
  smoothly between the Week and Hour densities; the playhead keeps its place while you zoom
  (the Day/Hour/Week pill included, which used to jump the scrub position).
- Timeline: cameras with nothing to show no longer collapse into a thin bar — the tile keeps its
  place in the grid with a proper placeholder.

### 0.3.3 — 2026-07-21
- Timeline: the screen now catches up the moment you return to it — reopening the app no longer
  shows a stale "last time" until the next background tick. Camera tiles pick up newly recorded
  footage as the timeline grows, so scrubbing to the present shows current previews instead of
  images frozen at the moment the screen was first opened.

### 0.3.2 — 2026-07-21
- Navigation: the tab icons now animate — switching tabs plays a little bounce on the selected
  tab's icon.

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
- Pinch-to-zoom + pan (1x–10x) on the live camera view, on both platforms.

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
