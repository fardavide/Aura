# Aura — agent guide

Aura is a native **iOS + macOS** client for **Frigate NVR** (self-hosted security
cameras with AI object detection). Personal-use, single-user, and a portfolio piece.
It's a third-party Frigate client. The MVP: a live camera grid, fullscreen single
camera with Picture-in-Picture, a minimal event list, and event-clip playback.

## Skills & commands

Project agent config lives directly under `.claude/` (committed, no `.ai/`
abstraction, no symlinks):

```
.claude/
  skills/<area>-<topic>/SKILL.md   ← project skill, invoked as /<area>-<topic>
  commands/<name>.md               ← project command, invoked as /<name>
CLAUDE.md                          ← this file (real file, committed)
```

Skills are **flat**: each lives at `.claude/skills/<name>/SKILL.md` and is invoked by
its directory name (Claude Code only discovers skills as direct children of the skills
root — no folder grouping). This is a personal project, so names stay plain — no team
namespacing prefix. Related skills may share a topical prefix where it helps (e.g. the
`frigate-` integration skills).

The user's **global** skills also apply and are not duplicated here — notably `tdd`,
`typing`, `test-doubles`, `scenario-pattern`, `refactor`, `architecture-review`, and
`skill-expert`. Prefer a global skill for language-general rules; add a project skill
only for Aura/Swift/Frigate-specific guidance.

### Project skills

| Skill | Use it for |
|-------|-----------|
| `/architecture` | Layering (Clean Architecture + MVVM), service layer, typed IDs, the cross-platform video/PiP wrapper, storage |
| `/swift-style` | Swift 6 / SwiftUI conventions — concurrency, optionality, exhaustive switch, init defaults, SwiftUI styling |
| `/swift-testing` | Swift Testing, the Scenario fixture, fakes, decoding tests |
| `/frigate-rest` | Frigate HTTP API — `/api/config`, `/api/events`, media URLs, JSON shapes, auth |
| `/frigate-live` | The go2rtc live stream URL for AVFoundation, src naming, codec/auth caveats |

### Project commands

| Command | Does |
|---------|------|
| `/build-test` | Build/test Aura for iOS Simulator + native macOS via `xcodebuild` |

## Tech stack (decided — do not substitute)

- Swift 6, strict concurrency = complete; `@MainActor` default isolation.
- SwiftUI + `@Observable` (modern Observation).
- Deployment target iOS 26.0 / macOS 26; **Multiplatform** (iPhone, iPad, native macOS).
- Video: AVFoundation / AVKit (`AVPlayerViewController` → free PiP on iOS).
- Networking: `URLSession` + async/await — **no Alamofire**. JSON: `Codable`.
- Storage: `UserDefaults` (server config + theme) + Keychain (password). No SwiftData,
  no CloudKit, no sync.
- Architecture: MVVM + a separate networking/service layer — see `/architecture`.
- Testing: **Swift Testing** (not XCTest). TDD.
- **Zero external dependencies.** SPM only.

## Platforms

Multiplatform target (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`,
device family `1,2`). `AVPlayerViewController` and `UIBackgroundModes` are iOS-only —
keep the player + PiP behind the platform wrapper in `/architecture`; don't
scatter `#if os(...)` through feature code. Do not re-narrow to iOS-only.

## Engineering principles

**When in doubt, ask.** Never guess an API, pattern, or convention. Reading code (or the
verified `/frigate-rest` / `/frigate-live` maps) is cheap; wrong guesses compound. This
applies especially to Frigate endpoint/param names and AVFoundation/Keychain APIs.

**Skill invocation discipline.** Before a non-trivial task, identify which skills apply
and invoke them **before** acting. If none apply, say so explicitly.

**TDD.** Failing test first, minimum to pass, then refactor. The build order per the
brief: networking/service layer + models (with decoding tests) → Settings → Live grid →
camera detail → Events list → event detail. (See the global `tdd` skill.)

**Strong typing & abstraction granularity.** Typed ID wrappers over primitives; no tiny
rename-only helpers. Details in `/swift-style`.

**Docs avoid rotting code refs.** When writing under `.claude/`, describe concepts and
contracts, not specific type/function names, unless a name is a genuine canonical anchor.

## Code search tooling

Prefer the `ast-index` skill for structured symbol / usage / hierarchy lookups in Swift
(initialize with `/ast-index:initialize-ios` if not yet configured). Fall back to
`rg`/`grep`/`find` via Bash. Reserve Bash for git, `xcodebuild`, and non-source work.

## Build & test

Use `/build-test`. Quick reference:

```bash
xcodebuild build -scheme Aura -destination 'generic/platform=iOS Simulator' -quiet
xcodebuild build -scheme Aura -destination 'generic/platform=macOS' -quiet
xcodebuild test  -scheme Aura -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Out of scope for the MVP (do not build)

Push notifications, continuous-recordings scrubbing, multi-server, health/stats
dashboard, PTZ, Frigate YAML config editor, Cloudflare Zero Trust / advanced auth.
Remote access is handled externally by Tailscale — the app treats the server as a
plain local-style HTTP endpoint (host, port default 5000, http/https, optional auth).
