---
description: Build and/or test Aura from the command line for iOS Simulator and native macOS
argument-hint: "[build|test|all] (default: all)"
---

## Your task

Build and test the Aura app. Input: `$ARGUMENTS` (`build`, `test`, or `all` — default `all`).

Aura is a **Multiplatform** target (iPhone/iPad + native macOS), so verify **both**
platforms — a change can compile on one and break the other.

Run from the repo root. The scheme is `Aura`.

### Build only (fast compile check, no device boot)

```bash
xcodebuild build -scheme Aura -destination 'generic/platform=iOS Simulator' -quiet
xcodebuild build -scheme Aura -destination 'generic/platform=macOS' -quiet
```

### Test (Swift Testing suite)

```bash
xcodebuild test -scheme Aura -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -scheme Aura -destination 'platform=macOS'
```

### Package tests via xcodebuild

`swift test` in `AuraKit/` stays the fast host-side default. To run the package suites through
`xcodebuild` (simulator or macOS), use the shared `AuraKitTests` scheme **from inside the package
directory** (Xcode Cloud can't run them at all — it resolves schemes through the app container;
see `.ai/docs/decisions.md`):

```bash
cd AuraKit && xcodebuild test -scheme AuraKitTests -destination 'platform=iOS Simulator,name=iPhone 17'
```

Do **not** run package test targets through the app project's container (repo root, `Aura` scheme
test plans, etc.) — xcodebuild silently drops them and errors with "There are no test bundles
available to test" (see `.ai/docs/decisions.md`).

### Screenshot tests

SwiftUI screen rendering is covered by **screenshot tests** in the app-hosted **`AuraTests`**
target (they need a real host window — see `.ai/docs/decisions.md`). They run via the same
`Aura` scheme and cover iPhone + iPad (both orientations) × **light + dark** on the **simulator** —
one sim run renders every config. macOS is intentionally excluded (AppKit can't capture glass faithfully).

```bash
xcodebuild test -scheme Aura -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:AuraTests/TimelineScreenSnapshotTests
```

- **Reference images** live in `AuraTests/__Snapshots__/` and are committed.
- **(Re)recording a baseline:** delete the stale `.png` (or the whole folder) and run — the
  first pass writes the missing reference and fails; xcodebuild's retry-on-failure then
  compares and passes in the same invocation. Inspect the new PNGs before committing.

### Notes

- Append `| tail -n 30` (with `set -o pipefail`) to keep output readable; the line you
  care about is `** BUILD SUCCEEDED **` / `** TEST SUCCEEDED **` or the first error.
- If `iPhone 17` isn't installed, pick another from
  `xcrun simctl list devices available`.
- A harmless `IDERunDestination: Supported platforms ... is empty` warning can appear
  during destination resolution — it does not mean the build failed; check the final
  status line.
- Don't pass `-destination 'generic/...'` to `test` — test needs a concrete simulator
  (or `platform=macOS`).
- Report the actual result honestly: if tests fail, show the failing output; never
  claim green without the success line.
