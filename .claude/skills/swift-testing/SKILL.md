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

## Handwritten fakes, never mocking frameworks

There is no mocking framework and we don't add one. Write `FakeXxx` types conforming
to the domain protocol, with observable state and invocation tracking:

```swift
final class FakeCamerasRepository: CamerasRepository {
    var result: Result<[Camera], CamerasError> = .success([])
    private(set) var camerasCallCount = 0

    func cameras() async throws(CamerasError) -> [Camera] {
        camerasCallCount += 1
        return try result.get()
    }
}
```

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

The app target's own tests (later, for Presentation/UI) run via `/build-test`.
