# Recording fast forward verification

Verified on 2026-10-11 and 2026-10-12. The local implementation covers the Timeline grid and
camera detail. Normal 1×/2× playback keeps the existing authenticated HLS and audio; 4×/8×
uses video-only native compositions in aligned 120-second windows. No server settings changed.
The branch is `fix/recording-fast-forward`, based on `4551f13` from `origin/main`.

## Automated checks

| Check | Result |
| --- | --- |
| Full host package suite, `swift test` | Passed |
| Full iOS Simulator package suite | 880 tests passed, 888 cases including parameters |
| iOS Simulator app build | BUILD SUCCEEDED |
| Native macOS app build | BUILD SUCCEEDED |
| Recording detail snapshots | 11 tests fail on this branch and untouched main |
| Timeline snapshots | 7 tests fail and 1 passes on this branch and untouched main |
| Whitespace validation | `git diff --check` passed |

The new regressions demonstrated failures before their fixes: stale speed loads, seeking under
a pending load, paused gap positions, forward/backward walks through empty fast windows,
loads reclaiming a drag, repeated fetches after a failed composition, and keyframe preroll on
a tiny boundary clip. Synthetic media verifies mapped video duration and absence of audio even
when audio timestamps extend the container. Ordinary pending fetches preserve a subsequent
Live request; the exact interleaving during awaited asset construction has no deterministic
test seam, so its generation guard was reviewed directly.

Snapshot failures are in dark glass backgrounds. Both suites were rerun on an isolated,
unchanged default-branch checkout at `4551f13`. Representative detail and Timeline failure
PNGs are byte-identical between that checkout and this branch. The existing references,
rendering code and comparison thresholds were preserved. These local iOS 27 comparisons are
red; they do not establish a failure in the pinned CI environment. A separate investigation
verified that the same default-branch revision passed all 79 snapshot tests in
[CI](https://github.com/fardavide/Aura/actions/runs/37318573818), using Xcode 26.6 build 17F113
and iOS 26.5. This machine has Xcode 27.0 build 27A266a and only an iOS 27.0 runtime. The
repository's Xcode selection action explicitly pins the older baseline environment.
The separate investigation also reproduced all 11 detail failures on an isolated iPhone 17
with iOS 27; a representative failure PNG was byte-identical to the iPhone 18 Pro render.
No source, baselines or tolerances were changed during that investigation.

## Decoded video on the real server

The probe exercised production grid view models and the shared player builder with all three
cameras against Frigate 0.18.0-77a66e7. Sources are H.264, 2688×1520, 20 fps. Each measurement
sampled decoded pixel buffers over six seconds after a two-second warm-up, with a 10 ms polling
interval. These are sampled decoded-frame counts, not a physical screen's refresh rate.

| iOS Simulator camera | 4× sampled fps | 8× sampled fps | Largest 8× frame gap |
| --- | ---: | ---: | ---: |
| front garden | 80.0 | 84.8 | 90 ms |
| back garden | 80.0 | 81.7 | 124 ms |
| garage | 77.5 | 80.3 | 54 ms |

All items became ready, reported fast-forward capability and had no media errors. Initial
readiness took 0.76–1.42 seconds on iOS Simulator. Native macOS sampled roughly 78–80 fps at
4× and 85–87 fps at 8×. The previous native HLS path produced about 0.5–0.7 fps at these rates.
The garage's gaps shorten its media clock; the shared wall clock still selects the requested
recording instant. Window transitions are covered by synthetic-media acceptance tests; the
short production sampling interval did not measure a real-file rollover.

## Evidence and remaining validation

Result bundles are retained locally under `/private/tmp/` with the `aura-fast-forward-` prefix:
`package-ios-final.xcresult`, `snapshots-retry.xcresult`, `baseline-snapshots.xcresult`,
`timeline-snapshots.xcresult` and `baseline-timeline-snapshots.xcresult`. Failure PNGs are saved
separately there. The temporary comparison checkout was archived after preserving evidence.

The [three-layout preview](https://chatgpt.com/space/page_af024c51ecd48191b060118e37dd10b4)
contains light/dark reference screens. Black video areas are test placeholders. Page creation,
embed insertion and readback were confirmed; the Page viewer itself was not visually inspected.

Physical iPhone performance, long-running real-file window transitions, authenticated remote
MP4 range access and PiP remain TestFlight validation items. Automated media probes used the
local API; the configured Tailscale address timed out while Tailscale was off. The local
verification preceded PR preparation; no release was performed.
