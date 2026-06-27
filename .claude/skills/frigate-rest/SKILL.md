---
name: frigate-rest
description: Frigate 0.17 HTTP REST API map — /api/config camera discovery, /api/events query params and event JSON schema, the media URLs (thumbnail / snapshot / clip / latest), and the auth model. The live go2rtc stream lives in frigate-live.
when_to_use: >
  Use when calling, modifying, or decoding any Frigate REST endpoint — listing or filtering
  events, discovering cameras and their enabled state, building thumbnail/snapshot/clip/latest
  image and video URLs, or mapping the wire JSON to domain models. Also when the user asks to
  "add an events filter", "load the camera list", or "fetch a thumbnail".
---

## Your task

Help work with the Frigate 0.17 HTTP API. This skill maps the endpoints, query
params, JSON shapes, and auth model the Aura client depends on, so you can build
and modify the networking/service layer without guessing.

Everything here is **stable REST** and was verified against the Frigate v0.17.1
source (`frigate/api/*.py`, `frigate/models.py`, `frigate/config/camera/camera.py`).
The one version-dependent piece — the live stream — lives in `frigate-live`.

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

## CRITICAL: never guess API contracts

Never fabricate query-param names, paths, body shapes, or response fields. If an
endpoint or param isn't mapped here:

1. Verify against the running instance or the v0.17 source
   (`github.com/blakeblackshear/frigate` at tag `v0.17.1`), **or** stop and ask.
2. Then **update this skill** — add the endpoint/param with its exact name and a
   one-line description, so the map stays accurate and grows.

Getting a param name wrong causes silent, hard-to-trace bugs.
