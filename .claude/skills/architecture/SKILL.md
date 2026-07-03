---
name: architecture
description: Aura's layering — Clean Architecture + MVVM, the networking/service layer, DTO↔domain mappers, typed IDs, the cross-platform video/PiP wrapper, and the UserDefaults/Keychain storage rules.
when_to_use: >
  Consult before adding a feature that spans layers, creating a ViewModel or service, deciding
  where code belongs (domain vs data vs presentation), wiring auth into media loads, or touching
  the macOS/iOS player split. Also when the user asks "where should this live?" or "add a service".
---

## Feature-vertical Clean Architecture

Code lives in the local SPM package **`AuraKit`**, organised **by feature** then by
layer, on shared `Common/*` infra targets:

```
AuraKit/Sources/
  <Feature>/Domain/         pure: entities, repository protocols, use cases, the feature's error
  <Feature>/Data/           DTOs, mappers, the Real (Frigate) repository implementation
  <Feature>/Presentation/   SwiftUI views + @Observable ViewModels
  Common/Network/           generic HTTP transport                         [infra]
  Common/Frigate/           the Frigate adapter — ServerConfig, endpoints, media URLs [infra]
```

Features: `Cameras`, `Events`, `Settings` — each one vertical slice, its own targets.

### The Dependency Rule (strict — the compiler enforces it)

Dependencies point **inward**; the Domain is the centre and depends on **nothing**.

```
<Feature>Presentation → <Feature>Domain   (pure)
                            ↑ implemented by
<Feature>Data ───────────────┘  → CommonFrigate → CommonNetwork   (infra)
```

- **Frigate is an implementation detail.** No Domain may import `CommonFrigate`,
  `CommonNetwork`, `URLSession`, a DTO, or anything Frigate-named — a Domain target
  doesn't list those as SPM dependencies, so it *cannot* compile against them.
- The concrete repository is named for its source — `FrigateCamerasRepository:
  CamerasRepository` — so the data source stays swappable.
- **Domain** = entities (`struct`/`enum`), repository **protocols**, **use cases**, and
  the feature's typed error. No `import SwiftUI`, Foundation networking, or AVFoundation.
- **Data** implements the domain protocols; DTOs are `internal` and mapped to domain
  models by pure mappers at the boundary. Never leak a `…DTO` outward.
- **Presentation** = SwiftUI views + `@Observable` ViewModels depending on **use cases**
  (never on a repository directly, `URLSession`, or a DTO).

### Dependency injection — constructor injection + composition root

Every class takes its collaborators through its **initializer**; no registry/service
locator is passed around. A small hand-written **composition root** in the app target
builds the graph (constructs `Frigate…Repository(config:httpClient:)`, wraps it in use
cases, injects those into ViewModels). Tests construct types directly with fakes and
never touch the composition root.

### Use cases

A use case is a small `struct` in the feature's Domain with a single
`execute(...) async throws(<Feature>Error) -> …` method (**not** `callAsFunction`), holding
its repository via constructor injection. ViewModels depend on use cases, not repositories.

### Screen self-load — refresh in place, never re-blank

A screen's `.task { await viewModel.load() }` re-runs on every appearance, so `load()` must
not reset state to `.loading` before fetching: only the very first load shows the full-screen
spinner (the initial state), a re-appearance **re-fetches behind the current content**, and a
failed refresh **keeps the last good content** rather than swapping it for a full-screen error.
Refreshing in place is preferred over skip-if-loaded (`loadIfNeeded`) so content also stays
fresh. The snapshot suite catches regressions here — a spinner in a "loaded" baseline means
the self-load blanked the screen.

## Typed IDs — never raw String

Domain identifiers get typed wrappers (`struct CameraName`, `struct EventId`, …) that
live in the **owning feature's Domain**, propagated through every signature, field, and
return type. Unwrap to `String` only at the `URLSession`/legacy boundary. This is the project instance of the global
**Strong Typing** rule — a `CameraName` passed where an `EventId` is expected must
not compile.

## Networking / data layer

- Request building, auth, decoding, and error mapping live in the **Data layer**: the
  feature's `Frigate…Repository` uses `Common/Frigate` (endpoints, `ServerConfig`, media
  URLs) over `Common/Network` (the `HTTPClient`). The Domain never sees any of it.
- **Auth reaches media too.** The `Authorization` header (Basic or Bearer — see
  `frigate-rest`) must be attached to JSON calls, image loads, AND the live
  `AVURLAsset`. Centralise header construction so all three share it:
  - Images: a small authenticated image loader (plain `AsyncImage` won't carry the
    header) feeding SwiftUI.
  - Live/clip video: `AVURLAsset(url:options:)` with `AVURLAssetHTTPHeaderFieldsKey`.
- Errors are explicit and typed (a domain error enum). No swallowed errors; surface
  failures to the UI as a state.

## Cross-platform video / PiP wrapper

Aura is **Multiplatform** (iPhone/iPad + native macOS — see the `macos-is-a-target`
memory). `AVPlayerViewController` and `UIBackgroundModes` are **iOS-only**. Put the
player + PiP behind one wrapper type with a platform split:

- iOS: `AVPlayerViewController` (free PiP).
- macOS: AVKit `AVPlayerView`.

Use `#if os(iOS)` / `#if os(macOS)` only inside that wrapper — the rest of the UI
stays platform-neutral SwiftUI. Don't scatter `#if os` through feature code.

## Storage (decided — keep it minimal)

- **UserDefaults**: server config + theme (theme is per-device, never synced).
- **Keychain**: the password only.
- **No** SwiftData, **no** CloudKit, **no** cross-device sync. Frigate is the source
  of truth; cameras/events are fetched fresh and are ephemeral. Don't add a
  persistence framework for a handful of settings.

## Dependencies

**Zero** third-party dependencies. SPM only, and only if it ever becomes truly
unavoidable (it shouldn't for the MVP). No Alamofire — `URLSession` + async/await.
