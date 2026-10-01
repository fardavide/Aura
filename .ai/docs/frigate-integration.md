# Frigate integration

What we learned wiring Aura to Frigate 0.17/0.18. Exact API contracts live in the `/frigate-rest` and
`/frigate-live` skills; this is the model and the *verified findings*.

## Connection model
Remote access is via Tailscale, so the app treats Frigate as a plain HTTP endpoint: host, port
(default 5000), http/https, optional auth. The API connection has a required remote address and
optional local address; a short local Frigate probe selects the active route. Live playback may
use its own scheme and port for each route, always on that route's existing host. A remote fallback
never borrows the local live port. API ports and credentials continue to serve all non-live media and reads.

## Auth — reality vs the brief
Frigate 0.17's *native* auth is **JWT** (port 8971: `POST /api/login` → cookie/Bearer); port 5000
is unauthenticated. The brief chose **HTTP Basic auth**, which fits hitting 5000 over Tailscale,
optionally behind a reverse proxy that adds Basic. Aura builds Basic and sends it on JSON *and*
media requests; Frigate JWT is a future extension (the auth-header construction is the one seam to
change).

## Live stream (Frigate 0.18)
AVPlayer needs HLS. The working URL is go2rtc's HLS endpoint:
`http://<host>:1984/api/stream.m3u8?src=<stream_name>`. The older *undocumented*
`/api/go2rtc/api/stream.m3u8?...` Frigate proxy worked in 0.16/0.17, but **0.18.0 removed its
general nginx location**. The [upstream 0.18.0 configuration](https://github.com/blakeblackshear/frigate/blob/v0.18.0/docker/main/rootfs/usr/local/nginx/conf/nginx.conf)
retains particular WebRTC routes, not a live-HLS proxy. The user's running 0.18.0 server also
returns **404** at the historical HLS proxy; previews still work because they use the API.

Configure an optional **live scheme and port under each API address**. Live playback always
shares that API address's host: go2rtc on the same server requires no third IP. An empty live
port retains the historical proxy for older installations; 0.18 needs compatible direct
go2rtc transport (usually HTTP on port 1984). Do not change the general API port. Frigate credentials
are sent only to the API/historical proxy, never to the separate live endpoint automatically.
Authentication on a separate go2rtc endpoint is outside this change.

New setups prefill HTTP/1984; saved transports and legacy proxy selections are retained.
Local and remote ports remain separate because remote forwarding can map to another port.
On 2026-10-02 the user confirmed playback worked in the updated app after setting 1984.

`src` names come from each camera's `live.streams` in
`/api/config`. **Confirm the actual `src` + reachability against the running instance before
shipping live video.** Caveats and the AVFoundation tradeoff: `/frigate-live`.

### Playback evidence (2026-10-01)

On `minisforum-m1`, the user established H.264 video and AAC audio for `front_garden_1`,
`back_garden_1`, and `garage_1`, and fetched/decoded HLS with FFmpeg. A native macOS AVPlayer
probe against the configured direct go2rtc endpoint then decoded **20, 20 and 21 frames**
respectively, all **2688×1520**, with playback advancing **2.00, 2.01 and 2.07 seconds**. No
credentials were sent. This verifies actual AVFoundation video playback, beyond fetching a
playlist or reaching `readyToPlay`. Physical iPhone/iPad playback, remote-network availability,
and Picture-in-Picture remain unverified by that probe.

The final probe used Aura's actual live-player model and kept its video output attached through
pause/resume, matching the mounted video layer. **All nine checks passed**: initial playback,
fresh-item Retry, and pause/resume for each stream, with 20–21 decoded 2688×1520 frames and
more than two seconds of advancing playback per check. Aura reached its playing state;
mute survived Retry. A deliberately missing stream reached Aura's failed state in **0.16 s**.

This caught an observer issue before delivery: AVFoundation's status callbacks fired, but the
enum change payload was nil on this Mac. Reading the observed status property before the main-actor
hop restored both playing and failed states. A native observer regression now covers the wiring;
tests that called the state handler directly had missed it.

## REST surface used
`/api/config` (cameras + `enabled` flag + stream names; also `camera_groups` and `record`
retention — see below), `/api/events` (list, and `?after=` for the grid's "today" tally),
`/api/review` (in-progress activity), `/api/stats` (recording-disk free/total), and media
(`latest.jpg`, `thumbnail.jpg`, `clip.mp4`). Event/review times are Unix epoch seconds; map at the
DTO boundary. Details: `/frigate-rest`.

### Recordings playback findings (verified against Frigate v0.17.2 source)
- **Recordings are single-resolution.** Frigate records only the stream carrying the `record` role;
  there is no second rendition to pick. The multi-stream map in `/api/config` is go2rtc **live**
  only. The one lower-res view of history is `preview.mp4` — what the scrub grid already uses.
- **The VOD playlist is gapless.** `/vod/{camera}/start/{s}/end/{e}/master.m3u8` welds the window's
  recordings into one sequence with `discontinuity` off, so **player time ≠ wall-clock time** and a
  seek must be converted by summing the footage before the target. The manifest builds each clip
  from the recording's reported `duration` (not `end − start`), trims it by the window overhang, and
  drops what falls under 100 ms or reaches `MAX_SEGMENT_DURATION` (600 s).
- **`MAX_PLAYLIST_SECONDS` is 7200**, so one clock hour per playlist is the safe unit.
- Exact rules, including the invisible keyframe-snap on a head-trimmed clip: `/frigate-rest`.

### Server cost of the overlay endpoints (verified against Frigate v0.17.2 source)
- **`/api/recordings/unavailable` can freeze the whole API.** `no_recordings`
  (`frigate/api/media.py`) is an **`async def`** — it runs on the API's event loop, not a worker
  thread — and computes gaps with a pure-Python scan that re-walks the window's recording rows for
  every `scale` bucket: O(buckets × rows). A 7-day window at ~300s scale is ~2000 buckets over
  ~60k rows per camera (one row per ~10s segment) — tens of seconds of CPU during which **every**
  API request (HA polls, the web UI, our VOD reads) hangs. Client timeouts don't help: the loop
  never awaits, so uvicorn finishes the scan even after the client hangs up.
- **`/api/review/activity/motion` is heavy but threaded.** A sync `def`: it loads every
  `motion > 0` recording row in the window into a pandas frame and resamples — seconds of CPU on a
  wide window, but it doesn't block the loop.
- **`/api/review` is a single indexed query** (overlap clause `start_time < before AND
  (end_time IS NULL OR end_time > after)` — in-progress items are in every window touching now)
  with a `limit`; cheap.
- **Contract for the client (0.5.1):** never query motion/gaps over more than ~a day; issue
  multi-day spans as sequential day windows (newest first) so the loop breathes in between;
  refresh only the live-edge delta. This is what the app ships; also worth filing upstream.

### Scoping the timeline overlays to one camera
`/api/review`, `/api/review/activity/motion` and `/api/recordings/unavailable` all take a
comma-separated `cameras=`. The client sends it only when narrowing to a camera and **omits it
entirely** for all cameras — the `cameras=all` sentinel is documented for `/api/events` but not for
these three, and omission is the shape already running in production. The motion `scale` (bucket
seconds) is still derived from the span, so a 7-day window comes back at roughly five-minute
resolution whatever the scope; the detail track draws its bars at that width rather than
interpolating a finer one.

### Cameras grid v2 findings (verified against Frigate v0.17.2 source)
- **`camera_groups`** is a top-level object in `/api/config`, keyed by group name →
  `{ cameras, icon, order }`. ⚠️ `cameras` is `Union[str, list[str]]`: the web UI writes a
  **comma-joined string**, so a client must decode both an array and a bare string (split on `,`).
  Membership may include the pseudo-camera `birdseye` (strip it). Sort by `order`.
- **`/api/stats` → `service.storage`** is keyed by mount path; the recordings volume is the fixed
  `"/media/frigate/recordings"` with `{ total, used, free }` in **MiB** (Frigate divides bytes by
  2²⁰). A mount absent on the host is simply omitted — treat every key as optional.
- **Retention has no single field in 0.17.** `record.retain.days` (≤0.13) is gone. The knobs are
  `record.continuous.days`, `record.motion.days`, `record.alerts.retain.days`,
  `record.detections.retain.days` (all `float`). We surface "days kept" as the **max** of the four.
