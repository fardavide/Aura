# Aura — agent guide

Aura is a native **iOS + macOS (Multiplatform)** SwiftUI client for **Frigate NVR** — a
personal, single-user, third-party client and portfolio piece.

## Read first

- **Before any non-trivial change**, read `.ai/docs/architecture.md` and `.ai/docs/decisions.md`
  so you don't break a layer boundary or re-litigate a settled decision (`.ai/docs/README.md`
  indexes them). **Keep them current**: record decisions in `decisions.md`, current state in
  `status.md`, Frigate findings in `frigate-integration.md`. Docs = the *why* and *where we are*;
  skills = actionable rules.
- **Invoke applicable skills before acting** on a non-trivial task; if none apply, say so.

Project skills (`.claude/skills/<name>`, invoked `/<name>`):

| Skill | Use it for |
|-------|-----------|
| `/architecture` | Layering (feature-vertical Clean Architecture + MVVM), composition root, typed IDs, the cross-platform video/PiP wrapper, storage |
| `/swift-style` | Swift 6 / SwiftUI conventions — concurrency, optionality, exhaustive switch, init defaults, styling |
| `/swift-testing` | Swift Testing, fakes, decoding tests, the screenshot tests |
| `/frigate-rest` | Frigate HTTP API — config, events, recordings/review/VOD timeline, media URLs, JSON, auth |
| `/frigate-live` | go2rtc live-stream URL for AVFoundation, src naming, codec/auth caveats |

Global skills also apply (e.g. `tdd`, `typing`, `test-doubles`, `refactor`, `skill-expert`) —
prefer a global skill for language-general rules; add a project skill only for Aura/Swift/Frigate
specifics. `/build-test` is the build/test command. `.claude/` is Claude-specific config; `.ai/docs/`
is agent-agnostic.

## Tech stack (decided — do not substitute)

- Swift 6, strict concurrency = complete, `@MainActor` default isolation.
- SwiftUI + `@Observable`; deployment target iOS 26 / macOS 26.
- Video: AVFoundation / AVKit (`AVPlayerViewController` → free PiP on iOS); Liquid Glass (`glassEffect`).
- Networking: `URLSession` + async/await (**no Alamofire**); JSON via `Codable`.
- Storage: `UserDefaults` (config + theme) + Keychain (password). No SwiftData/CloudKit/sync.
- Testing: **Swift Testing** (not XCTest), TDD, plus app-hosted screenshot tests.
- **Shipped code has zero dependencies.** The only dependency is `swift-snapshot-testing`, and it
  is **test-only** (the `AuraTests` app target). Don't add runtime/SPM deps.

## Architecture (see `/architecture` + `decisions.md` for detail)

- One local package `AuraKit`: each feature is `Sources/<Feature>/{Domain,Data,Presentation}` as
  separate SwiftPM targets, on shared `Common/*` infra. The app target wires it via a hand-written
  composition root (`AppComposition`).
- **Domain is pure** — no Frigate, no networking; enforced by target dependencies. "Frigate" lives
  only in Data/infra (e.g. `FrigateCamerasRepository`).
- **Constructor injection, no service locator.** Tests build types directly with fakes.
- **Typed throws**: `async throws(<Feature>Error)`. Typed ID wrappers over primitives.

## Conventions that differ from defaults

- **No consecutive uppercase** in our identifiers: `Dto`, `Url`, `Http`, `Id` (Apple's `URL`,
  `HTTPURLResponse`, etc. keep their spelling).
- `execute()`, never `callAsFunction`. Test names read `` `given X when Y then Z` `` (backtick raw
  identifiers).
- No default values in data-class primary inits (defaults belong in factories). No tiny rename-only
  helpers. In `.claude`/`.ai/docs`, describe concepts/contracts, not type/function names.

## Platforms

Multiplatform (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, device family `1,2`).
iOS-only APIs (`AVPlayerViewController`, `UIBackgroundModes`) stay behind the platform wrapper —
don't scatter `#if os(...)` through feature code, and **don't re-narrow to iOS-only**.

## Engineering principles

- **When in doubt, ask.** Never guess an API/param — especially Frigate endpoints and
  AVFoundation/Keychain. Reading code or the verified `/frigate-*` maps is cheap; wrong guesses compound.
- **TDD**: failing test first, minimum to pass, then refactor.
- **Verify before "done"**: builds + tests must pass, and show the evidence.

## Build & test

```bash
cd AuraKit && swift test                                                      # package logic tests (host)
xcodebuild build -scheme Aura -destination 'generic/platform=iOS Simulator' -quiet   # + 'generic/platform=macOS'
xcodebuild test  -scheme Aura -destination 'platform=iOS Simulator,name=iPhone 17 Pro'  # app + screenshot tests
```

- **`main` is PR-gated** (GitHub ruleset: required CI checks, no direct pushes) — land every change
  via a pull request and wait for the checks. **Fetch and rebase onto `origin/main` before
  committing**: the ruleset requires up-to-date branches, and sibling PRs often touch the same
  feature files — sync first so conflicts surface before work piles onto a stale base.
- Package tests via `xcodebuild` (simulator runs) use the shared `AuraKitTests` scheme **from
  inside `AuraKit/`** — the app project's container silently drops package test targets (see
  `/build-test` and `decisions.md`).
- Build **one platform at a time with `-jobs` capped** — back-to-back parallel `xcodebuild` once
  exhausted the macOS per-user process limit (`fork: resource temporarily unavailable`).
- **CI** (`.github/workflows/ci.yml`, GitHub-hosted `macos-26`) runs on push/PR to `main`. Snapshot
  baselines are re-recorded **locally**, never on CI. Xcode Cloud is **archive-only** — neither
  test suite can run there (see `decisions.md`).
- Prefer the `ast-index` skill for Swift symbol/usage lookups; fall back to `rg`/`grep`. Reserve Bash
  for git, `xcodebuild`, and non-source work.
</content>
