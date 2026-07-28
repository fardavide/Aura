---
name: swift-style
description: Aura's Swift 6 / SwiftUI code conventions — strict concurrency, optionality discipline, exhaustive switch, typed wrappers over primitives, no silent init defaults, SwiftUI styling (semantic colors, @Observable, theming system controls to a design), and documentation.
when_to_use: >
  Consult when writing or reviewing Swift production code — adding types, ViewModels, or SwiftUI
  views, choosing optionality or error handling, or naming things. Also when building a screen or
  control to a design mock, or when the user asks to "write the model", "add a view", "follow the
  design", or flags Swift style.
---

## Concurrency — Swift 6, strict

The project is Swift 6 language mode with **complete** strict concurrency and
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (code is MainActor-isolated by default).

- Types crossing actor/task boundaries must be `Sendable` — make value types
  `Sendable` rather than reaching for `@unchecked`.
- Don't pepper code with `@MainActor` — it's the default. Annotate the few things
  that must run **off** the main actor (e.g. heavy decode) explicitly.
- No `DispatchQueue` hopping for concurrency; use `async`/`await` and structured tasks.

## Optionality — don't introduce nullability on a whim

Don't make a type optional because "the caller might not have one". An optional defers
the decision and forces every downstream consumer to handle a `nil` that may represent
an impossible state. If you reach for `T?` in new design, **stop and ask** — surface
what `nil` would mean and the alternatives (a sentinel, an `enum` case, a required
parameter). Inheriting optionality from a system API is fine; inventing it is not.

- No force-unwraps (`!`) without a written justification on the line. Prefer
  `guard let` / `if let`. Force-try (`try!`) and force-cast (`as!`) are banned in
  production code.

## Exhaustive `switch` — no catch-all `default`

A `switch` over an `enum` enumerates **every** case. Don't add a `default:` that
swallows cases added later — it defeats the compiler's exhaustiveness check.

```swift
// ✓ — every case explicit; the compiler flags a new case
switch state {
case .idle, .loading: return nil
case .ready(let cameras): return cameras
case .failed(let error): throw error
}

// ✗ — default hides a newly-added case
switch state {
case .ready(let cameras): return cameras
default: return nil
}
```

## Typed wrappers, not primitives

Domain IDs/values get typed wrappers (`CameraName`, `EventId`, …) propagated through
every signature — see `architecture`. Never strip a wrapper to `String`/`Int`
for convenience; unwrap only at a legacy API call site.

## Naming — no consecutive uppercase

Our identifiers use single-capital segments, never runs of capitals: `Dto` not `DTO`,
`Url` not `URL`, `Http` not `HTTP`, `Api` not `API`, `Json` not `JSON`, `Id` not `ID`
(e.g. `ConfigDto`, `HttpClient`, `baseUrl`, `EventId`, `FrigateMediaUrl`). Apple's own
types keep their spelling — write `URL`, `URLSession`, `HTTPURLResponse`, `JSONDecoder`
as-is; the rule applies to names *we* define.

## Imports — grouped and alphabetical

Three groups separated by one blank line, each sorted alphabetically:

1. System frameworks (`Foundation`, `SwiftUI`, `Testing`, …)
2. Third-party (test-only, e.g. `SnapshotTesting`)
3. Project modules (`CamerasEntities`, `CommonPlayer`, …), with `@testable import` lines last

When adding an import, insert it in sorted position — never append at the end of a group.

## Member ordering

Within a type body, declare members in this order (the project port of the Kotlin
member-ordering convention):

1. Public stored properties
2. Private stored properties — hoisted up only when initialization order forces it
3. `init` (and `isolated deinit`)
4. Public methods — the type's API surface
5. Private methods
6. Remaining nested types

Settled exception: a ViewModel's `State` enum leads the type — it is the vocabulary the
properties below it are typed with. Free helpers and file-private types are top-level at
the **bottom of the file**, never inside the type. New members go into their group in
place — never appended at the end of the type.

## Initializers — no silent defaults on domain models

Don't give stored properties default values in a domain `struct`'s memberwise/primary
init — callers must pass every value so the compiler catches a missing one. Defaults
belong in **factory functions** (and test factories), not the type itself.

```swift
// ✓ — explicit; a new field breaks every call site until handled
struct CameraTile { let name: CameraName; let isEnabled: Bool; let previewURL: URL }

// ✗ — default hides missing data and silently absorbs new fields
struct CameraTile { var name: CameraName; var isEnabled: Bool = true }
```

## Values & immutability

Prefer `struct`/`enum` over `class`; prefer `let` over `var`. Make invalid states
unrepresentable with enums rather than boolean/optional soup.

## Error handling

Explicit and typed. Repository/use-case boundaries use **typed throws** —
`func cameras() async throws(CamerasError) -> [Camera]` — so the error type is part of the
signature. The error is a **domain** enum owned by the feature (`CamerasError`, …) with
domain-level reasons, never HTTP/Frigate vocabulary; the Data layer maps transport and
decoding failures into it. No swallowed `catch {}`. Keep mappers and computations pure;
isolate side effects at boundaries.

## Abstraction granularity

Don't add a tiny helper (function, computed property, extension) that just renames or
slightly shortens an inline expression — every new name is a memory tax on the reader.
Inline it unless the helper encapsulates non-trivial logic, is reused 3+ times with a
clear meaning, or its name makes intent substantially clearer.

## SwiftUI

- **Semantic system colors only** — no hardcoded hex. Both light and dark mode are
  first-class; an explicit theme picker (System/Light/Dark) lives in Settings. Theme
  is per-device.
- Use `@Observable` view models (modern Observation), injected via the view's init.
  No `ObservableObject`/`@Published` for new code.
- **Pin an injected view model in `@State` when the view runs `.task` work against it** —
  `@State private var viewModel` + `_viewModel = State(initialValue: viewModel)`, not a
  plain `let`. The composition root builds view models inline in `RootView.body`, so every
  parent re-evaluation hands the view a fresh, unloaded instance; a `let` swaps the
  *displayed* model while the running `.task` closures (which rebind only on appearance)
  keep driving the discarded one — the 0.3.9 permanent Timeline spinner. `@State` keeps
  the first instance for the view's identity lifetime; rebuild deliberately via `.id(...)`
  (as RootView does per connection). A plain `let` is fine only when the instance is
  pinned upstream (`PreviewTileView` via `TileStore`) or the view does no async work
  against it.
- Keep views small and composable; push logic into the ViewModel. The camera grid is
  the centerpiece — keep it clean and minimal.
- Embrace iOS 26 / Liquid Glass styling where it comes for free; don't fight the system.

### Building to a design: theme the system control, don't hand-roll one

When a design mock shows a control, find the **system control with that behavior** and theme it
(font, weight, `monospacedDigit`, sizing, `buttonStyle`, background/tint) until it reads like the
mock. A four-rung speed ladder is a segmented `Picker`; a translucent chip with a border and a soft
shadow is `.buttonStyle(.glass)` — the mock is *describing* the system look, so reproducing its
hex values by hand is both more code and worse (no dark mode, no Dynamic Type, no platform drift).
Build a custom component only when **no** system control has the behavior, and say why.

Two failure modes this rule sits between, both real:

- **Don't substitute a different control** and call it done — a menu button instead of the mock's
  visible ladder loses what the design was communicating. Match the *affordance*, then theme it.
- **Don't ship a default that reads badly in context.** A stock segmented picker over the glass
  scrubber card washes out; `.font(.footnote.weight(.bold))` + `.fixedSize()` made the same control
  legible and closer to the mock than the default was.

**Verify styling against rendered pixels, not intuition.** Re-record the affected snapshot and look
at the PNG. If a styling modifier makes no difference, delete it: `.tint()` on a segmented `Picker`
is a **no-op** (the selection indicator is not tinted by it) — proven by an A/B of the recorded
image, byte-identical with and without. A modifier that does nothing is a false claim about the UI.

**Finishing UI work means showing the screens, not describing them.** Whenever a change touches the
UI, end the turn by showing the user **three** rendered screens: **iPhone portrait, iPhone landscape,
iPad**. They are the three compositions every screen has to survive, and the snapshot baselines
already contain them — never ask the user to run anything to see their own work.

**Publish them as an Artifact page, not as raw image files.** The user reads on mobile, where loose
PNGs often can't be opened. Downscale the baselines (`sips -Z <width> -s format jpeg`), inline them
as data URIs, and publish one page. Two things that page must do: swap between the light and dark
baselines with the viewer's theme (the app ships both, so show both), and say which parts are
placeholder — a black rect where video would be — so nothing reads as broken.

## Documentation

Don't add comments that restate the code — a well-named declaration needs none. A
comment earns its place only by explaining a non-obvious *why*, a gotcha, or a
constraint the code can't express. When in doubt, leave it out.
