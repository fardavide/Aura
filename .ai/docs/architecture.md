# Architecture

Aura is **Clean Architecture, organised feature-vertically** inside a local Swift package
(`AuraKit`), with a thin app target on top. For the actionable rules use the `/architecture`
skill; this is the map and the *why*.

## Layers, per feature

Each feature (`Cameras`, `Events`, `Settings`, `Timeline`) splits into three layers, each its own
SwiftPM target:

- **Domain** — entities, value types, repository *protocols*, use cases, the feature's error.
  Pure: depends on nothing (no networking, no Frigate, no SwiftUI).
- **Data** — DTOs, mappers, and the concrete repository (`Frigate…Repository`) implementing the
  Domain protocol via the shared infra. "Frigate" only ever appears in this layer.
- **Presentation** — SwiftUI views + `@Observable` view models that depend on Domain use cases.

A type referenced by **more than one feature's Domain** moves to the owning feature's pure
`<Feature>Entities` target (e.g. `CamerasEntities`: `CameraName`, `CameraStreamSource`) — zero
dependencies, imported by the other features. Per-feature entity modules, never one global kernel.

Shared infrastructure lives under `Common/*` targets:
- **Common/Network** — generic HTTP transport (`HttpClient`) + auth header.
- **Common/Frigate** — the Frigate adapter: `ServerConfig`, endpoint + media URL builders.
- **Common/Keychain** — secret-storage abstraction.

## The dependency rule (compiler-enforced)

Dependencies point inward; a feature's **Domain depends on nothing**, so it *cannot* import a
DTO, `URLSession`, or anything Frigate — the SwiftPM target simply doesn't list them. The data
source is an implementation detail behind a Domain protocol; the cameras repository is a
`Frigate…Repository`, swappable without touching Domain or Presentation.

## Composition & DI

No service locator. Every type takes its collaborators through its **initializer**. A single
**composition root** in the app target wires the graph and maps the domain `ConnectionSettings`
to the infra `ServerConfig`. Tests construct types directly with fakes and never touch the root.

## App shell

The app target hosts only the composition root + a root view that routes between the camera grid
(when a connection is configured) and Settings, and applies the theme. Multiplatform: iOS +
native macOS; iOS-only APIs (PiP, background audio) stay behind a platform wrapper.

## Storage

`UserDefaults` for non-secret connection config + per-device preferences (theme, camera order);
Keychain for the password. No SwiftData/CloudKit/sync — Frigate is the source of truth;
cameras/events are fetched fresh. Preferences consumed outside the Settings editor are **observed**
(the repository exposes a stream: current value, then changes), never re-read on appear.
