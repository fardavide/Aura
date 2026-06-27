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
