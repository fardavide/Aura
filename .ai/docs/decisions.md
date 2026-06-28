# Decisions

Key choices and why (ADR-style, newest last). Several were settled with the user during design —
**check here before re-litigating.**

## Multiplatform (iOS + macOS), not iOS-only
The scaffold is a Multiplatform target and the user wants the native macOS build kept. Don't
re-narrow `SUPPORTED_PLATFORMS`. iOS-only APIs go behind a platform wrapper.

## One local package, feature-vertical, lean targets
`AuraKit` holds many small targets organised `<Feature>/<Layer>` + `Common/*`. Chosen over a
single app target (boundaries by discipline only) and over per-feature micro-packages (more
ceremony). Feature-vertical so the app scales as features grow rather than one giant Domain.

## Strict dependency rule — Frigate is an implementation detail
No Domain may depend on Frigate/networking; enforced by SwiftPM target dependencies, not
discipline. The concrete repo is named for its source (`FrigateCamerasRepository`).

## DI: constructor injection + composition root (no service locator)
Collaborators are passed via initializers; a hand-written composition root wires them. A
`Provider`/registry was considered (the user's other apps use one) but rejected for the core app
to keep dependencies explicit and compiler-checked. Tests bypass the root entirely.

## Errors: Swift 6 typed throws
Repository/use-case boundaries use `async throws(<Feature>Error)` — idiomatic, and the error type
is part of the signature. Each feature owns its domain error; the Data layer maps
transport/decoding failures into it (no HTTP/Frigate vocabulary in the Domain).

## Testing: Swift Testing, given/when/then, handwritten fakes
`@Test` with `given … when … then …` backtick names mirroring the body markers. Handwritten fakes
over mocking frameworks; test data via small local helpers.

## Naming: no consecutive uppercase
Our identifiers use single-capital segments (`Dto`, `Url`, `Http`, `Id`). Apple's own types
(`URL`, `URLSession`, `HTTPURLResponse`, `JSONDecoder`) keep their spelling.

## Settings & connection config
Minimal Settings (connection + theme). Non-secret config → `UserDefaults`, password → Keychain.
The Domain has a pure `ConnectionSettings`; the composition root maps it to the infra
`ServerConfig` (slight duplication accepted to keep the Domain infra-free).

## Authed grid images via a Domain protocol
Grid tiles load `latest.jpg` with auth. The loader is a Domain protocol implemented in Data, so
Presentation never imports Frigate infra and the auth header still reaches images.

## Agent config layout
Behavioral rules → `.claude/skills` (flat, plain names). Commands → `.claude/commands`. Narrative
findings/decisions/status → `.ai/docs/` (tool-agnostic). No `.ai` symlink scheme for skills.
