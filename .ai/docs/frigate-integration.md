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
`/api/config` (cameras + `enabled` flag + stream names), `/api/events` (list), and media
(`latest.jpg`, `thumbnail.jpg`, `clip.mp4`). Event times are Unix epoch seconds; map at the DTO
boundary. Details: `/frigate-rest`.
