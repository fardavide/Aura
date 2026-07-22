---
name: frigate-live
description: The Frigate 0.17 + go2rtc LIVE stream — the AVFoundation-compatible HLS URL (port 1984), stream src naming, codec/latency caveats, the undocumented Frigate proxy path, and how auth reaches the media. REST endpoints live in frigate-rest.
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

### Through Frigate's auth (no exposed 1984) — caveat

Frigate does **not** expose a dedicated live-HLS proxy path. The only route that
reaches go2rtc's HLS through Frigate is, by nginx prefix-replacement:

```
http(s)://<host>:8971/api/go2rtc/api/stream.m3u8?src=<STREAM_NAME>
```

(GET-only, behind Frigate JWT auth.) This works but is **undocumented** — that
nginx location exists to fetch the go2rtc version, not as a streaming API, so it
could change between releases. Prefer exposing 1984 directly when the network is
trusted; use this proxy only when you must go through Frigate's auth.

> ⚠️ **Re-verify this proxy on every Frigate upgrade.** The go2rtc internal API /
> WebSocket and its `exec`/`echo`/`expr` sources are being actively hardened
> upstream, so the `/api/go2rtc/…` location sits in churning auth code. It survived
> 0.17.1 → 0.17.2 untouched, but treat a quick "does live still play through the
> proxy?" check as part of every version bump. The direct `:1984` path is the
> fallback if it ever 403s or moves.

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
  required (the 8971 proxy path, or a Basic-auth reverse proxy), pass headers via
  `AVURLAsset(url:options:)` with `AVURLAssetHTTPHeaderFieldsKey`
  (`Authorization: Bearer <jwt>` or `Basic ...`). The direct 1984 path on a trusted
  network needs no auth.
- Set up the `AVAudioSession` for background playback at launch and enable the
  audio Background Mode (already configured in the project) so PiP keeps playing.

---

## CRITICAL: confirm before assuming

The stream `src` and whether 1984 is reachable vs. the 8971 proxy is needed both
depend on the specific deployment. Confirm the actual playing URL against the
running instance, then record the working shape here so it's not re-derived.
