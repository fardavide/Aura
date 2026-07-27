---
ticket: no-ticket
status: accepted
superseded-by:
---

# No-ticket: Timeline transport on the scrubber card + full-resolution tiles

## Context

The Timeline screen today is scrub-only: dragging the Liquid-Glass scrubber moves one shared
`ScrubClock`, and every `PreviewTileViewModel` follows it by seeking a low-res hourly
`preview.mp4` (past hours) or showing the nearest `.webp` preview frame (the live hour), coalesced
per tile by `PreviewTileController`. There is no play button anywhere on the screen — playback
only exists on the **pushed** single-camera screen added in 0.3.13 (`RecordingPlayerViewModel` +
`RecordingControlBar`), reached by tapping a tile.

The design (`Timeline.dc.html`, Option A) puts the transport on the scrubber card itself:
*"Play/pause runs playback forward at 1–8×, skipping over no-footage gaps and stopping at the live
edge."* Its control row is `[⟲10] [play/pause] [10⟳]` on the left and a 4-segment `1× 2× 4× 8×`
pill on the right — the same affordances `RecordingControlBar` already renders, so the bar is
reusable rather than new. Placement differs per layout: bottom card (iPhone portrait), the vertical
card (iPhone landscape), transport on the right of a wide card (iPad), a bottom inspector bar (Mac).

Settled by the user for this slice: the Timeline screen itself must play **full resolution**, not
only the low-res scrubber material. That **reverses** the 0.3.13 decision, which reads: *"The grid
keeps its low-res preview scrubbing — that is what Frigate's own web client does, and a wall of
full-res HLS streams is not viable on a phone; full resolution lives on the pushed screen."* The
options below are the ways to honour the new requirement; each says what it costs.

Constraints that frame the fork (verified, `/frigate-rest` + the 0.3.13 decision):

- **Recordings are single-resolution.** Frigate records only the `record`-role stream. "Full
  resolution" therefore means the VOD HLS (`/vod/{camera}/start/{s}/end/{e}/master.m3u8`) — there
  is no middle rendition between it and `preview.mp4`.
- **One clock hour per playlist.** `MAX_PLAYLIST_SECONDS` is 7200 and the web UI chunks by the
  hour; `RecordingWindow.containing` already returns whole hours, and `RecordingTimeline` already
  maps wall clock ↔ player time (gaps removed) in both directions. Per-tile full-res playback is a
  **reuse** of `GetCameraRecordings`, not new data-layer work.
- **Two clocks will fight.** The transport advances a wall-clock instant; each HLS player advances
  its own. With N independent players there is no shared timebase, so tiles drift and must be
  re-seeked against the transport clock past a tolerance. One player (Option 2) removes the problem
  entirely; N players (Options 1/3) make it a permanent, approximate correction loop.
- **Cost is per-stream, not per-player.** The tile count already means N concurrent `AVPlayer`s
  today, so the decode-session count is unchanged — what changes is bitrate: N × full-res instead
  of N × 180px VFR. On a phone over LAN/Tailscale this is the whole risk.
- **Rates above 2× on HLS are not dependable.** `AVPlayer` honours high `rate` on HLS only when the
  server publishes I-frame-only playlists; nginx-vod-module's `master.m3u8` is not known to. The
  1–8× ladder is safe for the *transport clock*, but 4×/8× may degrade to stepping rather than
  smooth full-res playback — a fallback to preview material at high speed is the escape hatch.
- **AVPlayer against Frigate's VOD is still unproven on a real server** (0.3.13's stated risk;
  Frigate's own client always uses hls.js). Every option inherits that risk; Option 2 inherits the
  least of it because it is the same single stream 0.3.13 already built.

Wiring is unaffected in shape: `AppComposition.previewTileViewModel(for:connection:)` builds each
tile and already builds `GetCameraRecordings` next door in
`recordingPlayerViewModel(for:at:connection:)` — a tile that plays full-res takes the same use case
through its initializer. No new scope, no new binding, no service locator.

Version: this is a user-visible feature slice, so `/versioning` puts it at a **minor** bump —
`MARKETING_VERSION` 0.3.13 → **0.4.0**, `CURRENT_PROJECT_VERSION` 29 → **30**, plus a README
changelog entry.

## Options Considered

### Option 1: Every tile swaps to full-res while playing

A new `TimelinePlaybackController` (Timeline/Presentation) owns `isPlaying` + `PlaybackSpeed` and
advances `ScrubClock` on a timer, jumping over `DayTimeline` gaps and stopping at `span.end`.
`PreviewTileViewModel` gains a playback mode: on play, each tile fetches
`GetCameraRecordings.execute(for:in: RecordingWindow.containing(instant))`, builds an authed player
on `RecordingPlayback.source`, and runs it at `speed.rate`; on pause or on a scrub it tears the
stream down and reverts to the existing preview material. Drift against the transport clock is
corrected by the existing `PreviewTileController` coalescing path.

- **Pro:** exactly the literal ask — press play on the Timeline and every camera shows real
  footage. The grid stays homogeneous, so the design's four layouts need no new affordance.
- **Pro:** all the hard parts already exist and are unit-tested (`RecordingTimeline`,
  `RecordingWindow`, window-swap-at-the-hour, gap handling) — this is composition, not new domain.
- **Con:** N × full-res HLS concurrently is the exact thing 0.3.13 ruled out. Eight cameras at
  1080p is plausibly tens of Mbit/s; on a phone this is where it will fall over first.
- **Con:** N independent players cannot be frame-synced — tiles will visibly disagree by a second
  or so, and each hour boundary makes all N reload at once.
- **Con:** at 4×/8× the likely outcome is N stuttering streams rather than fast playback.

### Option 2: One focused tile plays full-res, the rest keep previews

The transport on the card drives the shared clock as in Option 1, but only **one** camera streams:
the focused tile (tap to focus in place; long-press or a second tap still pushes the existing
full-screen `RecordingPlayerView`). The focused tile hosts what is effectively today's
`RecordingPlayerViewModel` inline, and the *stream's* own clock becomes the master the transport
reads — so the readout, the histogram playhead and the other tiles all follow real footage
instead of a synthetic timer. Unfocused tiles keep preview scrubbing and follow that clock.

- **Pro:** viable on a phone and honest about bandwidth — one stream, whatever the camera count.
- **Pro:** removes the two-clocks problem outright: there is one authoritative playback clock, so
  the readout can never disagree with the picture.
- **Pro:** mirrors Frigate's own recordings view (one main player, previews around it) and keeps
  the 0.3.13 decision intact rather than reversing it.
- **Con:** does not satisfy "high-res on the Timeline" in the strongest reading — only the focused
  camera is full-res at any moment.
- **Con:** needs a focus affordance and a focused-tile treatment that the design does not draw, and
  it competes with the existing tap-to-push gesture.

### Option 3: Bounded full-res — visible tiles up to a cap, with speed-based fallback

Option 1's mechanism, explicitly bounded: full-res is granted to at most K tiles (K ≈ 4) that are
actually on screen, in grid order; the rest keep previews, and **every** tile falls back to preview
material above 2× where HLS trick-play is unreliable. The cap and the fallback live in the
`TimelinePlaybackController` as a pure policy value, so it is unit-testable without a player.

- **Pro:** the literal ask wherever it is affordable, with a defined failure mode instead of an
  unbounded one — a 12-camera server degrades predictably rather than collapsing.
- **Pro:** the policy is a pure function (visible set + speed → who streams), so it is covered by
  package tests even though the players themselves cannot be.
- **Con:** the most moving parts of the three, and behaviour changes as you scroll — the same tile
  is full-res or not depending on position, which is hard to explain and hard to snapshot.
- **Con:** still N-way drift among the K streaming tiles (Option 1's sync problem, just smaller).
- **Con:** K is a guess until it is measured on the real server, which has not happened yet.

## Decision
Selected **Option 1: Every tile swaps to full-res while playing** — see the option above for details.

## Consequences

Shipped as **0.4.0** (build 30). What the implementation settled beyond the option itself:

- **`TimelineTransport` drives the shared `ScrubClock`; it streams nothing.** Play/pause and the
  speed ladder move the one instant the histogram, readout and tiles already follow, so the grid is
  synchronised by construction. The two-clocks problem named in Context is answered by making the
  transport clock authoritative and every tile a follower that corrects its own drift (1s tolerance)
  and swaps hours when the playhead leaves the one it streams.
- **The advance rule is a pure type** (`TimelinePlayhead`): forward at the speed, over gaps in
  ascending order so adjacent gaps clear in one pass, stopping at the live edge. Unit-tested without
  a clock or a player.
- **Playing scrolls the histogram instead of moving the playhead** (it is centre-fixed by design),
  and the scroll→clock direction is switched off while playing so rounding can't feed back. A
  gesture-driven scroll phase pauses playback; `.animating` — our own re-anchor — does not.
- **Play from the live edge rewinds a minute**, which incidentally closes the separate "resuming at
  the live edge" follow-up from 0.3.13.
- **An hour with no footage isn't a tile failure**: the tile falls back to preview material, marks
  that hour abandoned so the ~10 Hz follow can't refetch it, and rejoins full resolution at the next
  hour that has footage.
- `RecordingWindow` / `RecordingTimeline` / `GetCameraRecordings` were reused unchanged — the tile
  is a second consumer of 0.3.13's machinery, so the hour rules and gap mapping have one
  implementation. The only Data-layer change is composition: tiles now take `GetCameraRecordings`.
- Snapshot suite gained a **playing** state; it is deterministic because the injected `now` is
  frozen, so the tick loop measures zero elapsed time and can't move the playhead mid-capture.

Cost accepted, and unverifiable here: N concurrent full-res HLS streams, on top of 0.3.13's standing
"AVPlayer vs Frigate VOD is unproven" risk. Bitrate at the real camera count and whether 4×/8× is
smooth or steps are the two things to check on the running server — tracked in `status.md`.
