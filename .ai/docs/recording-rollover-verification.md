# Recording fast-forward window transitions

The iPhone report describes a brief “No footage at this time” message after roughly two
minutes of recording time, followed by resumed playback. At 8× this corresponds to fifteen
seconds of elapsed playback. Fast-forward compositions cover aligned 120-second windows.

The detail player previously requested the following window only after its native end
notification. Its periodic observer maps the exhausted item onto the recording's exclusive
end, where the loaded timeline reports no footage. The grid likewise began loading only
after its shared clock crossed the window boundary. Asset construction therefore sat on
the transition path. This explains an artificial boundary delay; genuine recording gaps
remain a separate state and must retain their existing behavior.

Work is isolated from the Xcode migration and based on main `5a48558`.

## Regression evidence

- A continuous 120-second synthetic composition at 8×, with the following request held
  open, did not request the next window at recording time 5039 before boundary 5040.
  The tile suite ran 17 tests: the new test failed and the other sixteen passed.
- Preparing one following window while current footage plays made all seventeen pass.
- Crossing that boundary during the pending preparation requested the window twice:
  eighteen tile tests ran, with only the new reuse test failing (three calls versus two).
- Reusing the pending preparation made all eighteen tile tests pass.
- An initial native-seek diagnostic did not establish callback delivery and passed on
  unchanged code. It was removed; it is not counted as reproduction evidence.

Twelve new behaviors were reproduced on the preceding implementation before their fixes:
tile preparation and request reuse; detail preparation and boundary footage state; growing
window freshness in both surfaces; obsolete player callbacks; paused native player readiness;
repeated preparation coalescing; speculative failure recovery; concurrent recovery consumers;
and recovery after a failed foreground retry. The readiness fixture uses the checked-in
recording video to construct a continuous two-minute composition. An isolated post-green
review identified the failure and growing-window cases, which received their own red/green
cycles before the final full run.

## Final automated verification

- Full host `swift test` passed on Xcode 27.0 / macOS 27.0.1.
- The package-owned simulator scheme passed all 892 tests with zero failures and zero skips
  on iPhone 17 / iOS 27.0 (24A434). Native result bundle:
  `/private/tmp/aura-rollover-package-ios-reviewed.xcresult`.
- Both generic iOS Simulator and native macOS app builds completed with `BUILD SUCCEEDED`,
  using serial invocations capped at four jobs. Derived data:
  `/private/tmp/aura-rollover-app-ios-dd` and `/private/tmp/aura-rollover-app-macos-dd`.
- The pinned iOS 26.5 PR snapshot gate remains pending; local iOS 27 cannot certify those
  references, as established separately during the Xcode migration investigation.
- No snapshot references, tolerances, package dependencies, deployment targets, or CI gates
  changed in this worktree.

These tests verify native readiness, transport state, request reuse, and stale callback
rejection. They do not measure rendered-frame continuity on a physical iPhone or a live
Frigate server. Real media handoff remains a post-merge TestFlight verification item.
