# Frigate integration

What we learned wiring Aura to Frigate 0.17. Exact API contracts live in the `/frigate-rest` and
`/frigate-live` skills; this is the model and the *verified findings*.

## Connection model
Remote access is via Tailscale, so the app treats Frigate as a plain HTTP endpoint: host, port
(default 5000), http/https, optional auth. Settings captures exactly this.

## Auth — reality vs the brief
Frigate 0.17's *native* auth is **JWT** (port 8971: `POST /api/login` → cookie/Bearer); port 5000
is unauthenticated. The brief chose **HTTP Basic auth**, which fits hitting 5000 over Tailscale,
optionally behind a reverse proxy that adds Basic. Aura builds Basic and sends it on JSON *and*
media requests; Frigate JWT is a future extension (the auth-header construction is the one seam to
change).

## Live stream (verified against go2rtc source + Frigate nginx, 0.16/0.17)
AVPlayer needs HLS. The working URL is go2rtc's HLS endpoint:
`http://<host>:1984/api/stream.m3u8?src=<stream_name>`. Frigate does **not** expose a dedicated
live-HLS path; the only route through Frigate's auth is the *undocumented*
`/api/go2rtc/api/stream.m3u8?...` proxy. `src` names come from each camera's `live.streams` in
`/api/config`. **Confirm the actual `src` + reachability against the running instance before
shipping live video.** Caveats and the AVFoundation tradeoff: `/frigate-live`.

## REST surface used
`/api/config` (cameras + `enabled` flag + stream names; also `camera_groups` and `record`
retention — see below), `/api/events` (list, and `?after=` for the grid's "today" tally),
`/api/review` (in-progress activity), `/api/stats` (recording-disk free/total), and media
(`latest.jpg`, `thumbnail.jpg`, `clip.mp4`). Event/review times are Unix epoch seconds; map at the
DTO boundary. Details: `/frigate-rest`.

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
