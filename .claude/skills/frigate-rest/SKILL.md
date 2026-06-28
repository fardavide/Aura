---
name: frigate-rest
description: Frigate 0.17 HTTP REST API map — /api/config camera discovery, /api/events query params and event JSON schema, the media URLs (thumbnail / snapshot / clip / latest), the recordings / review / VOD timeline endpoints (scrubbable playback), and the auth model. The live go2rtc stream lives in frigate-live.
when_to_use: >
  Use when calling, modifying, or decoding any Frigate REST endpoint — listing or filtering
  events, discovering cameras and their enabled state, building thumbnail/snapshot/clip/latest
  image and video URLs, building the recordings/review timeline (review segments, motion
  activity, recording segments + gaps) or VOD scrub-playback URLs, or mapping the wire JSON to
  domain models. Also when the user asks to "add an events filter", "load the camera list",
  "fetch a thumbnail", or "build the timeline / scrub recordings".
---

## Your task

Help work with the Frigate 0.17 HTTP API. This skill maps the endpoints, query
params, JSON shapes, and auth model the Aura client depends on, so you can build
and modify the networking/service layer without guessing.

Everything here is **stable REST** and was verified against the Frigate v0.17.2
source (`frigate/api/*.py`, `frigate/models.py`, `frigate/config/camera/camera.py`).
The 0.17.1 → 0.17.2 step left this surface contract-identical (a security/maintenance
patch); the event/review handlers are byte-identical across 0.17.0 → 0.17.2. The one
version-dependent piece — the live stream — lives in `frigate-live`.

---

## Base URL & ports

The app composes a base URL from: scheme (`http`/`https`) + host + port. Two ports matter:

| Port | Meaning | Auth |
|------|---------|------|
| `5000` | Internal API — the brief's default. | **Unauthenticated.** Intended to sit behind a trusted boundary (Tailscale) or a reverse proxy. |
| `8971` | Authenticated UI/API. | Frigate **JWT** (see Auth below). TLS by default (often self-signed). |

All REST paths below are relative to `<scheme>://<host>:<port>` and prefixed `/api`.

---

## Auth (important — diverges from "HTTP basic auth")

Frigate 0.17's **native** auth is **JWT**, not HTTP basic auth:
- `POST /api/login` with body `{"user": "...", "password": "..."}` → sets a
  `Set-Cookie: frigate_token=<jwt>`; the token is also accepted as
  `Authorization: Bearer <jwt>`.
- Port `8971` enforces it; port `5000` skips it.
- ⚠️ The cookie name `frigate_token` is **configurable** via `auth.cookie_name` in
  the Frigate config — don't hard-code it if/when the JWT seam is implemented; read
  it (or accept the `Authorization: Bearer` form, which is name-independent).

The Aura brief specifies **optional HTTP basic auth** + default port `5000`. That
is coherent **only** if Frigate is reached either (a) on `5000` with no auth over
Tailscale, or (b) behind a reverse proxy that adds HTTP basic auth. The app's
`Authorization` header (Basic or Bearer) must reach **media** loads too
(AVURLAsset, image loads), not just JSON calls — see `architecture`.

> If the deployment actually needs Frigate's own JWT, that's a real change to the
> auth layer — surface it, don't silently assume Basic.

---

## Endpoints the app uses

### Cameras — `GET /api/config`

Returns the full (password-sanitised) Frigate config as JSON. Cameras live under a
top-level object keyed by camera name:

```jsonc
{ "cameras": { "<camera_name>": { "enabled": true, "friendly_name": "...", "live": { "streams": { "Friendly": "<go2rtc_src>" } }, "webui_url": null, "zones": { } } } }
```

- **Enabled camera names** = keys of `cameras` whose `enabled == true`
  (`enabled: bool` defaults to `true` in `CameraConfig`).
- `friendly_name` (nullable) — display name; fall back to the key.
- `live.streams` — `Dict<friendlyName, go2rtcStreamName>`; the **values** are the
  valid `src` names for the live stream (see `frigate-live`).
- `/api/config` is heavy. `GET /api/stats` is the lighter endpoint for runtime
  state but does **not** carry the enabled flag — `config` is the source of truth
  for the camera list.

### Events list — `GET /api/events`

Returns a **JSON array** of event objects (newest first by default). Key query params:

| Param | Type | Default | Notes |
|-------|------|---------|-------|
| `cameras` | string | `all` | Comma-separated camera names (`camera` singular also accepted) |
| `labels` | string | `all` | Comma-separated object labels (`label` also accepted) |
| `zones` | string | `all` | Comma-separated zones |
| `limit` | int | ~100 | Page size |
| `before` / `after` | float | — | Unix epoch seconds window |
| `has_clip` | bool | — | Filter to events with a recorded clip |
| `has_snapshot` | bool | — | Filter to events with a snapshot |
| `in_progress` | bool | — | Currently-active events |
| `include_thumbnails` | bool | `false` | When false, the `thumbnail` field is omitted (we use the thumbnail.jpg endpoint instead — keep this off) |
| `sort` | string | `date_desc` | e.g. `date_desc`, `date_asc`, `score_desc` |

For the MVP event list, `GET /api/events?limit=...` (optionally `&cameras=` /
`&labels=`) is enough. Don't request `include_thumbnails` — load the image lazily.

### Event object — client-relevant fields

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Event id — wrap as a typed `EventId`, not raw `String` |
| `camera` | string | Camera name |
| `label` | string | Detected object, e.g. `person`, `car` |
| `sub_label` | string? | Nullable |
| `start_time` | double | **Unix epoch seconds** |
| `end_time` | double? | Unix epoch seconds; **null while `in_progress`** |
| `has_clip` | bool | Gate clip playback on this |
| `has_snapshot` | bool | |
| `zones` | [string] | |
| `top_score` / `score` | double | Marked-for-removal in the model; read score from `data` |
| `false_positive` | bool? | |
| `data` | object | `{ box, region, score, top_score, type, attributes, ... }` |
| `thumbnail` | string? | base64 JPEG — present **only** with `include_thumbnails=1` |

`start_time`/`end_time` are epoch seconds (decode as `Double`, convert to `Date`
at the mapper boundary).

### Media URLs

| Purpose | Route | Key query params | Content-Type |
|---------|-------|------------------|--------------|
| Event thumbnail | `GET /api/events/{id}/thumbnail.{jpg\|webp\|png}` | `format` (`ios`\|`android`, default `ios`), `max_cache_age` | image/jpeg |
| Event snapshot | `GET /api/events/{id}/snapshot.jpg` | `bbox`, `crop`, `height`, `quality`, `timestamp`, `download` (all bool/int) | image/jpeg |
| Event clip | `GET /api/events/{id}/clip.mp4` | `padding` (int seconds) | video/mp4 |
| Camera latest still | `GET /api/{camera}/latest.{jpg\|webp\|png}` | `height`, `quality` (default 70), `bbox`, `timestamp`, `zones`, `mask`, `motion`, `regions`, `paths`, `store` | image/jpeg |

- Grid tiles: `GET /api/{camera}/latest.jpg?height=<tile px>` is the cheap static preview.
- Event clip playback: `GET /api/events/{id}/clip.mp4` (only when `has_clip`).
- These are plain `GET`s — the auth header must be attached the same way as JSON
  calls (see Auth).

---

## Recordings, review & VOD playback (the timeline)

For the **timeline** feature (multi-cam scrub + per-camera recordings scrubber). Verified
against v0.17.2 source. Same base + auth as above; **all timestamps are Unix epoch seconds**
(decode `Double`, map to `Date` at the boundary).

### Review — cross-camera activity segments

A *review item* is a **time period of activity** (not a per-object event): `alert`
(person/car by default), `detection` (everything else), or `significant_motion`. These are the
timeline's colored markers — distinct from `/api/events`.

| Purpose | Route |
|---------|-------|
| Activity segments (markers) | `GET /api/review?cameras=&labels=&zones=&severity=&reviewed=0\|1&limit=&before=&after=` |
| Per-day counts (day badges) | `GET /api/review/summary?cameras=&labels=&zones=&timezone=` |
| Motion-intensity strip | `GET /api/review/activity/motion?cameras=&before=&after=&scale=<sec>` |

- Review item: `{ id, camera, start_time, end_time (null while in-progress), severity, thumb_path, data{ objects, zones, audio, detections, … }, has_been_reviewed }`. `/api/review` defaults to the last 24h; ordered severity asc then start_time desc.
- `review/summary` → `{ last24Hours:{reviewed_alert,reviewed_detection,total_alert,total_detection}, "YYYY-MM-DD":{…same four…} }`.
- `review/activity/motion` → `[{ start_time(int s), motion(0–100), camera }]`; `scale` = bucket seconds (default 30).

### Recordings — what footage exists

| Purpose | Route |
|---------|-------|
| Recording **segments** (ground truth) | `GET /api/{camera}/recordings?after=&before=` |
| Per-camera hourly rollup | `GET /api/{camera}/recordings/summary?timezone=` |
| All-cameras day availability | `GET /api/recordings/summary?cameras=&timezone=` |
| **Gaps** (no footage) — *new in 0.17* | `GET /api/recordings/unavailable?cameras=&after=&before=&scale=` |
| Per-camera disk usage | `GET /api/recordings/storage` |

- Segment: `{ id, start_time, end_time, duration(s), motion(int?), objects(int?), segment_size(MB) }`, ordered by start asc; default window = last hour.
- ⚠️ **Shape gotcha:** the **per-camera** `…/recordings/summary` returns a **list** of day objects (`{day, events, hours:[{hour,events,motion,objects,duration}]}`); the **all-cameras** `/api/recordings/summary` returns a **map** `{ "YYYY-MM-DD": true }`. Don't share one model.
- `recordings/unavailable` → `[{ start_time(int s), end_time(int s) }]` gaps; `scale` default 30.

### VOD — the scrub / playback target

| Purpose | Route |
|---------|-------|
| **Scrub playback (HLS)** | `GET <base>/vod/{camera}/start/{s}/end/{e}/master.m3u8` |
| HLS across gaps | `GET <base>/vod/clip/{camera}/start/{s}/end/{e}/master.m3u8` (forces discontinuity) |
| HLS for one event | `GET <base>/vod/event/{event_id}/master.m3u8` (`padding`) |
| Low-res scrub preview (range) | `GET /api/{camera}/start/{s}/end/{e}/preview.mp4` (`max_cache_age`) |
| Frame at a time | `GET /api/{camera}/recordings/{frame_time}/snapshot.{jpg\|png}?height=` |
| Range export (download only) | `GET /api/{camera}/start/{s}/end/{e}/clip.mp4` |

### Preview — the multi-cam synced scrub grid

How Frigate's Review "Motion" grid scrubs cheaply (each tile, two modes by time):

| Purpose | Route |
|---------|-------|
| Preview **clip list** (past hours) | `GET /api/preview/{camera}/start/{s}/end/{e}` |
| Preview **frame list** (current hour) | `GET /api/preview/{camera}/start/{s}/end/{e}/frames` |
| One preview **frame** (.webp) | `GET /api/preview/preview_{camera}-{ts}.webp/thumbnail.webp` |

- ⚠️ **The `/api/preview/` prefix is required.** The naive `/api/{camera}/start/{s}/end/{e}` form is **wrong** — it collides with the recordings routes. `camera` may be `all`.
- Clip list → `[{ camera, src (leading-slash path), type:"video/mp4", start, end }]`; the playable URL is `<base> + src` (drop the leading slash). The mp4 is low-res VFR (~1–2 fps, 180px, `+faststart` → **AVPlayer range-seekable**) — scrub it **locally** (`AVPlayer.seek(to:toleranceBefore:toleranceAfter:)`, ~0.5s tolerance); no network per scrub once buffered. There is one preview.mp4 **per hour per camera**.
- Frame list → `["preview_{camera}-{ts}.webp", …]` (full filenames). Show the nearest as the scrub handle moves; each `.webp` is `Cache-Control: max-age=1yr` (immutable) — lean on `URLCache`. iOS decodes WebP natively.
- Range arg rounding mirrors the web UI: clip list uses `round()`, frame list uses `floor()`/`ceil()` on the epoch-second bounds.
- **Scrub sync (client):** one shared scrub clock → call each tile's `scrubToTimestamp(t)`; throttle with a per-tile **in-flight guard** (coalesce: if a seek/load is pending, store the latest target; re-issue on completion only if it differs by > tolerance). **Not** a timer debounce. Budget for an initial buffering burst (N tiles = N concurrent preview.mp4 loads); buffer lazily/visible-first on iOS.

**Playback rules (verified + adversarially checked):**
- **HLS to scrub, MP4 to download.** Feed `/vod/.../master.m3u8` to AVPlayer; never the progressive `clip.mp4` for in-app playback on iOS (Frigate's own docs say Safari/iOS mishandle progressive mp4).
- **`/vod/` is served at the ROOT — no `/api` prefix.** `clip.mp4`, `preview.mp4`, `recordings`, `snapshot` ARE under `/api`. (The FastAPI `/api/vod/…` route returns a JSON manifest, not m3u8 — clients use the root `/vod/…` that nginx-vod-module serves.)
- **Bound the window to ~1 hour.** nginx-vod fails past a per-playlist segment cap (~1200+ segments). The web UI chunks the day into ≤1h windows, plays one, swaps playlists when scrubbing crosses the edge — mirror this; don't request a multi-hour playlist.
- **Player time ≠ wall-clock.** The HLS playlist concatenates segments with gaps removed; map a timeline timestamp ↔ player time by summing segment durations from `/api/{camera}/recordings`. For gapped windows use `/vod/clip/…`.
- **AVPlayer scrubbing Frigate's VOD is unproven** — the web UI uses hls.js on every platform, never the native player. **Verify on the real server before building on it.**
- **Auth on media:** port 5000 = unauthenticated. On 8971, HLS auth uses an nginx query-string `secure_token` (`?token=`) — custom `AVURLAssetHTTPHeaderFieldsKey` headers do **not** reliably reach HLS *segment* sub-requests, so prefer the token there.

---

## CRITICAL: never guess API contracts

Never fabricate query-param names, paths, body shapes, or response fields. If an
endpoint or param isn't mapped here:

1. Verify against the running instance or the v0.17 source
   (`github.com/blakeblackshear/frigate` at tag `v0.17.2`), **or** stop and ask.
2. Then **update this skill** — add the endpoint/param with its exact name and a
   one-line description, so the map stays accurate and grows.

Getting a param name wrong causes silent, hard-to-trace bugs.
