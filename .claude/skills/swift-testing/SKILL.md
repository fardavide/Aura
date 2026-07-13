---
name: swift-testing
description: Aura's test conventions — Swift Testing (not XCTest), the Scenario fixture, given/when/then structure, handwritten fakes over mocks, async testing, and Codable decoding tests against fixtures.
when_to_use: >
  Use when writing or reviewing test code — adding a @Test, building a Scenario, writing a fake,
  or testing decoding/async behavior. Also when the user asks to "write a test", "add a fake",
  or "test the decoder".
---

## Framework — Swift Testing, never XCTest

Use **Swift Testing** (`import Testing`, `@Test`, `#expect`, `#require`) for all new
tests. No XCTest. Follow TDD — write the failing test first (the global `tdd` skill
owns the red-green-refactor loop; this skill owns the Swift-specific shape).

## Scenario fixture

Each test type uses a `private struct Scenario` (or `final class` when it must hold
mutable observation state) that builds the system under test from fakes. No global
setup. Declare `Scenario` at the **bottom** of the test type, after the tests.

```swift
private struct Scenario {
    let http = FakeHTTPClient()            // exposed — tests stub/inspect it
    let sut: FrigateCamerasRepository

    init(config: ServerConfig = .test) {
        sut = FrigateCamerasRepository(config: config, httpClient: http)
    }
}
```

- Each test makes a fresh `Scenario` in its body.
- Constructor params are **higher-level model values** (cameras, an error to throw),
  never fake instances.
- Expose a fake as a `let` only when a test inspects it; otherwise inline it in the
  SUT init. Don't hoist test data to type/`static` level — each test owns its data in
  its `// given`.

(See the global `scenario-pattern` skill for the cross-language rationale.)

## Structure — `// given` / `// when` / `// then`

Each marker appears at most once, in order:

```swift
@Test
func enabledCamerasAreDecodedFromConfig() async throws {
    // given
    let scenario = Scenario()
    scenario.http.stub(status: 200, body: configJSON)

    // when
    let cameras = try await scenario.sut.cameras()

    // then
    #expect(cameras.map(\.name) == [CameraName("driveway")])
}
```

When construction itself is the action, use `// given - when`. When asserting only on
state produced by init, omit `// when`.

## Test names — given / when / then

Name each `@Test` as a `given … when … then …` sentence with a **backtick raw identifier**
(Swift 6.2+); `given` is optional when there's no precondition. The name mirrors the
`// given / when / then` body markers.

```swift
@Test func `given a disabled camera when getting cameras then it is excluded`() async throws { … }
@Test func `when building a basic header then credentials are base64 encoded`() { … }
```

Group with `// MARK:`.

## Fakes live in the shared `TestDoubles` target

All doubles for **public** protocols live in the `TestDoubles` SwiftPM target
(`AuraKit/Tests/TestDoubles`, one `public` type per file), exported as the
`AuraKitTestDoubles` product so the app-hosted `AuraTests` imports them too. Never
declare a fake privately inside a test file. One **configurable** fake per collaborator
(`var result`, invocation counters) — no `StubXxx` / `EmptyXxx` / `CountingXxx`
variants; every double is named `FakeXxx`. Sole exception: a double for an internal
seam (e.g. a presentation-internal protocol) stays in the owning test target, since the
shared module cannot see the protocol — but still in **its own file** there, never
inline in a test file.

## Handwritten fakes, never mocking frameworks

There is no mocking framework and we don't add one. Every double is a `FakeXxx` class named
after the protocol it implements — never `Stub-`, `Mock-`, `No-`, or `Empty-` — configurable
through its initializer, with invocation tracking added only when a test asserts on it:

```swift
public final class FakeCamerasRepository: CamerasRepository, @unchecked Sendable {
    public var result: Result<[Camera], CamerasError>
    public private(set) var fetchCount = 0

    public init(_ result: Result<[Camera], CamerasError>) { self.result = result }

    public func cameras() async throws(CamerasError) -> [Camera] {
        fetchCount += 1
        return try result.get()
    }
}
```

**Fakes live in the shared `TestDoubles` package target** (`AuraKit/Tests/TestDoubles`, one
file per fake, all `public`) — exported as a **test-only** library product that the package
test targets and the app-hosted `AuraTests` both import; it is deliberately not part of the
`AuraKit` product, so it never links into the app. Don't declare a private double inside a
test file — reuse or extend the shared fake. Exception: a fake for an *internal* protocol
(e.g. the Timeline preview scrubber) stays private in the owning feature's test target,
because the shared target can't see the protocol.

(See the global `test-doubles` skill for the fake conventions.)

## Assert on distinct, meaningful values

Use values that fail loudly if the wrong thing flows through — not defaults/placeholders.
Never call a production mapper inside an assertion; compare against a pre-built expected
value (a `fakeXxx()` or literal) so the test catches mapper bugs instead of mirroring them.

## Async & decoding

- Test async APIs directly with `await`; use `confirmation` for callback/delegate paths.
- **Model decoding gets its own tests:** decode a checked-in fixture JSON (a real
  Frigate `/api/events` / `/api/config` response shape) into the domain model and assert
  the mapped fields — especially epoch-seconds → `Date` and typed-ID wrapping. This is
  the first slice of the TDD build per the brief.

## Running tests

Package tests run on the macOS host — fast, no simulator:

```bash
cd AuraKit && swift test
```

The app target's own tests (incl. screenshot tests) run via `/build-test`.

## Screenshot (snapshot) tests

SwiftUI screen rendering is covered by **screenshot tests** using `swift-snapshot-testing` — the
**one** external dependency, **test-only** (linked to the `AuraTests` target in the Xcode project,
never `Package.swift`, so the app stays dependency-free).

- **They live in the app-hosted `AuraTests` target, not the package.** Only an app-hosted target has
  a real host window, so the full screen lays out and Liquid Glass renders (`drawHierarchyInKeyWindow:
  true`). Package test targets are hostless → blank screen, no glass. Don't move them back.
- **Pin every nondeterministic input** so the same pixels render on any machine: a fixed instant
  injected into the view-model, plus `.environment` for locale (`en_US_POSIX`) and calendar + time
  zone (GMT). A view that reads `Calendar.current`/`Date()` directly isn't snapshottable — thread the
  value through the SwiftUI environment instead.
- **Cover both light and dark.** Theme is a first-class app feature, so every screen is captured in
  both — loop the color scheme (`.environment(\.colorScheme,…)` + matching `UITraitCollection`
  userInterfaceStyle) and suffix the snapshot name with the scheme.
- **No async mid-flight in the captured frame.** A self-loading view (`.task { load() }`) must settle
  before capture, or you snapshot a spinner. Pre-drive the view-model to its terminal state and make
  the load idempotent so the view's `.task` doesn't reset it. Force data-dependent tiles/players into a
  stable placeholder — live video never renders in a snapshot.
- **Capture across the device matrix** (iPhone + iPad, both orientations) × light + dark on the
  simulator; use a perceptual-precision tolerance (glass isn't pixel-identical across OS versions). **macOS is excluded** —
  AppKit's offscreen `cacheDisplay` can't capture glass/materials/`ContentUnavailableView` (renders
  light/blank), so faithful macOS snapshots aren't achievable; don't retry without a different renderer.
- **Recording baselines:** delete the stale reference and run the suite — the first run writes the
  missing PNG and fails, a re-run compares (xcodebuild's retry-on-failure does both in one invocation).
  Commit the reference PNGs. Reference images live in `__Snapshots__/` beside the test file.
- **Inspecting a failure:** on a mismatch the freshly-rendered image is written to
  `AuraTests/__SnapshotFailures__/<Suite>/<name>.png` (gitignored) — same relative path as its
  `__Snapshots__/` baseline, so you can diff the two directly. `SnapshotSupport` pins this via
  `SNAPSHOT_ARTIFACTS`. On CI the failure job turns this folder into a browsable HTML diff report
  (`.github/scripts/snapshot-report.py`) uploaded as the `snapshot-diffs` artifact — no `.xcresult`.
