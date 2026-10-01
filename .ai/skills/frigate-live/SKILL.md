---
name: frigate-live
description: Maps Frigate 0.17/0.18 and go2rtc live streaming for AVFoundation, including HLS URLs, local/remote endpoints, source names, codecs, latency, proxying, and auth. Use when building or debugging live camera playback or PiP.
when_to_use: >
  Use when building or debugging the live camera view — choosing or fixing the go2rtc stream
  URL for AVPlayer/AVURLAsset, resolving the stream src name, handling HLS codec/latency issues,
  or making auth reach the live media. Also when the user asks to "show the live camera",
  "fix the stream", or "make PiP work".
---

## Your task

Wire up the live camera view. Frigate bundles **go2rtc**; the live stream URL is
the one Frigate-version-dependent thing in the whole app, so this skill records
exactly what was verified (go2rtc source + Frigate v0.16.4/v0.17.2 `nginx.conf`)
and adversarially confirmed. As of 0.17.2 the bundled go2rtc is **v1.9.10** and the
`/api/go2rtc/` nginx location is unchanged from 0.17.1 (verbatim, GET-only, behind
`auth_request`).

> **Verify against the running instance before shipping.** The exact stream `src`
> names depend on the user's `go2rtc.streams` config. Confirm the chosen URL plays
> against the actual server, per the project brief — don't hardcode a guessed `src`.

---

## Why HLS

AVFoundation (`AVPlayer` / `AVPlayerViewController`) natively plays **HLS**
(`.m3u8`). go2rtc's lower-latency transports (WebRTC, MSE/fMP4-over-WebSocket) need
a non-AVPlayer stack, so HLS is the right choice for a native client — at the cost
of latency (go2rtc's README literally calls HLS its worst-latency option; expect
multiple seconds). Acceptable for a security-camera live view; if sub-second
latency is ever required, that's a WebRTC/MSE effort, not an AVPlayer tweak.

---

## Frigate 0.18: configure live transport on the selected host

Frigate **0.18.0 removed the general `/api/go2rtc/` nginx proxy**. Its
[nginx configuration](https://github.com/blakeblackshear/frigate/blob/v0.18.0/docker/main/rootfs/usr/local/nginx/conf/nginx.conf)
retains particular WebRTC/WebSocket routes, but none proxies HLS. On the running
0.18.0 deployment, `/api/go2rtc/api/stream.m3u8?src=…` returns **404**.

- Keep Frigate's API address for previews, configuration, events and recordings.
- Configure a **live scheme/port under each local/remote API address**. Live
  playback reuses that selected address's host: no third IP or independent live
  host setting is needed when go2rtc runs on the same server. Never reuse the
  local live port on the remote route, or assume port 1984 is exposed remotely.
- Empty live ports retain the historical Frigate proxy for older deployments.
  On 0.18 direct live transport is required unless a user-managed proxy provides
  the historical route. Do not change server configuration to supply it.
- **Never copy Frigate credentials to direct go2rtc.** Direct sources have empty
  headers. Authentication for a separate live endpoint requires its own explicit
  design; hostname equality is not authorization to share credentials.
- Port **1984 is go2rtc's default**, separate from the API port. Do not hardcode
  a deployment host, add independent host fields without a demonstrated need,
  or silently rewrite the configured API port.

## The stream URL

Primary, on a trusted LAN/Tailscale network (expose go2rtc port **1984**):

```
http://<host>:1984/api/stream.m3u8?src=<STREAM_NAME>
```

- Default output is HLS/**TS, H.264, no audio** → maximally AVPlayer-compatible.
- Append `&mp4` for HLS/**fMP4** (supports H264/H265/AAC). Use for HEVC sources
  (needs iOS 17+/recent macOS). Filters: `&video=h264`, `&audio=aac`.
- **Avoid** Frigate's `+`/"smart" codecs (`h264+`/`h265+`) — they strip keyframes
  and break restreaming.

go2rtc default ports: API/web **1984**, RTSP 8554, WebRTC 8555.

### Historical Frigate proxy (verified only in 0.16/0.17)

Frigate 0.16/0.17 did **not** expose a dedicated live-HLS proxy path. Its general
go2rtc proxy reached HLS by nginx prefix-replacement:

```
http(s)://<host>:8971/api/go2rtc/api/stream.m3u8?src=<STREAM_NAME>
```

(GET-only, behind Frigate JWT auth.) This was **undocumented** — that
nginx location exists to fetch the go2rtc version, not as a streaming API, so it
could change between releases. Prefer exposing 1984 directly when the network is
trusted; use this proxy only when you must go through Frigate's auth.

> **Do not assume this proxy exists on 0.18.** Direct HLS uses the explicitly
> configured go2rtc endpoint; it is never an automatic credential-bearing retry.

> The `/vod/*.m3u8` and `/stream/*.m3u8` paths are nginx-vod-module HLS for
> **recordings/exports**, not live — don't use them for the live view.

---

## Stream `src` naming

`src` is a go2rtc **stream key**, defined by the user under `go2rtc: streams:` in
the Frigate config — Frigate does **not** auto-create one stream per camera.

- Discover valid `src` values from the camera's `live.streams` map in
  `GET /api/config` (the map's **values** are the go2rtc stream names) — see
  `frigate-rest`.
- Convention is `src = <camera_name>` for the main stream and `<camera>_sub` for a
  substream, but that's a convention, not a guarantee — read the config.

---

## AVFoundation integration

- Build the URL, then `AVURLAsset(url:)` → `AVPlayer`. The live view hosts the player in a **bare
  `AVPlayerLayer`** (so pinch-zoom scales only the video and our own controls stay put), with PiP
  driven by an app-owned `AVPictureInPictureController` — **not** `AVPlayerViewController`/
  `AVPlayerView`. Keep it behind the `CommonPlayer` wrapper described in `architecture` (see the
  "bare-layer video host" decision for why the earlier free-PiP approach was reversed).
- **Auth on the media load:** plain players won't carry credentials. When auth is
  required for the historical Frigate proxy, pass headers via
  `AVURLAsset(url:options:)` with `AVURLAssetHTTPHeaderFieldsKey`
  (`Authorization: Bearer <jwt>` or `Basic ...`). Direct live addresses never
  inherit these headers.
- Set up the `AVAudioSession` for background playback at launch and enable the
  audio Background Mode (already configured in the project) so PiP keeps playing.

---

## CRITICAL: confirm before assuming

The stream `src` and whether 1984 is reachable vs. the 8971 proxy is needed both
depend on the specific deployment. Confirm the actual playing URL against the
running instance, then record the working shape here so it's not re-derived.

### Verified 0.18 deployment (2026-10-01)

The user verified H.264/AAC in `front_garden_1`, `back_garden_1`, and `garage_1` on
`minisforum-m1` and decoded each with FFmpeg. A native macOS AVPlayer probe then
verified the direct `/api/stream.m3u8?src=<stream>` endpoint: 20/20/21 decoded
2688×1520 video frames with playback advancing >2 seconds for each stream.
The probe used no Authorization headers. This establishes AVFoundation playback,
not merely playlist retrieval. Physical iOS/iPadOS, remote-network reachability,
and PiP verification remain separate checks; do not claim them from a Mac probe.

The final Aura-player probe passed initial playback, fresh-item Retry and pause/resume
for all three streams (nine checks); its video output stayed attached across pause.
An invalid source became a visible failure state in 0.16 s. Initial loading and stalls
are bounded to 15 seconds; deliberate pause, backgrounding and audio interruption
cancel the loading deadline. Verify registered AVFoundation observers, not just their
handlers: enum KVO change values were nil on the test Mac despite valid status changes.
