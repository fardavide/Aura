# Xcode 27 migration verification

The user authorized draft PR publication and minimum-runtime validation on a temporary CI
runner. Merge, archive settings, and developer-machine configuration remain separate approvals.
The migration worktree is
`build/xcode-27-migration`. Initial recording and repeatability evidence used main at
`4551f13c6e0bdc48ab7d2b9beddbe07b7f09c085`. The playback fix was published in
[its own PR](https://github.com/fardavide/Aura/pull/74), passed all four required checks,
and merged independently. The migration is now rebased onto its main commit
`5a485581c462feb20c19856dd9f69a82f9553fd0`; final checks are being repeated there.

## Environment and support

Local Xcode is 27.0 build 27A266a; the installed iOS simulator is 27.0 build 24A434.
The test-owned iPhone 17 is `C58B8741-A8A7-4F75-9946-9F559D590E3F`.
Its boot completed before the full app-hosted comparison run began. Main's references
were copied to `/private/tmp/aura-xcode27-original-snapshots` before recording changes.

The app minimums stay iOS 26.0 and macOS 26.5; the package keeps iOS/macOS 26 minimums.
Language settings, package pins, dependencies, and app version remain unchanged.
This machine has no iOS 26 runtime. Minimum iOS validation runs on a provisioned temporary CI
runner; native macOS 26.5 remains unverified. Xcode Cloud stays
archive-only; availability of Xcode 27 in the actual archive workflow is unconfirmed.

## Acceptance evidence

The original inventory is 592 reference PNGs across nine directories. Full app-hosted
inventory is 79 tests in 11 suites. Preserve the image paths, suite membership,
capture configurations, and 0.98/0.87 comparison thresholds.

| Check | Status |
| --- | --- |
| Missing exact Xcode fails without fallback | RED observed, then GREEN |
| Wrong Xcode build fails visibly | RED observed, then GREEN |
| Missing exact runtime and ready test-owned device output | Two RED/GREEN cycles passed |
| Full iOS 27 comparison against old references | 79 tests: 47 passed, 32 failed; 63 image mismatches |
| Reviewed local iOS 27 reference candidate | 79/79 recording/comparison tests passed; all 592 panels reviewed |
| Two full local comparisons against candidate | Both 79/79 passed on initial frozen main; updated-main comparison also 79/79 passed |
| Full host package suite | Passed; 940 unique tests across 18 bundle summaries, exit 0 |
| Full iOS package suite | 880 passed, zero failed/skipped, exit 0 |
| iOS and macOS app builds | Both BUILD SUCCEEDED, exit 0 |
| iOS 26 runtime compatibility | Runtime provisioned in CI; compatibility gate remains red |
| Native candidate CI | All four existing checks passed on published candidate `2ca4511` |

The original comparison is preserved in `/private/tmp/aura-xcode27-old-baselines.xcresult`
and `/private/tmp/aura-xcode27-old-reference-report/index.html`. After test rendering
completed, verbose simulator diagnostics took another 600 seconds and timed out; the
result bundle then finalized with exit 65. The local recording invocation uses the
verified `-collect-test-diagnostics never` option for its deliberate missing-reference
failures. CI diagnostic collection and artifact retention remain unchanged.

Four hermetic CI-script tests pass. A fresh review found no blocking script/workflow
defects and confirmed preservation of all four required check names. Exact runtime
build matching on the hosted runner remains part of candidate CI acceptance.

The candidate bundle is `/private/tmp/aura-xcode27-record-candidate.xcresult`:
79 passed, zero failed/skipped, exit 0 and `TEST SUCCEEDED`. Candidate paths and image
dimensions match the original 592-image inventory exactly. All 592 PNG byte hashes
changed; no byte-identical reference needed restoration.

Visual review covered all 72 contact sheets / 592 candidate panels and 11 full-resolution
original-versus-current pairs. Coverage is retained at
`/private/tmp/aura-xcode27-visual-review/reviewer-coverage.md`; thumbnails do not establish
592 full-resolution comparisons or control effects. Reviewed changes include glass
tint/opacity/shadows, failure-message wrapping with readable actions, and the time
readout losing a leading zero. The affected readout uses default hour digits; explicit
two-digit ruler formatting is unchanged. No new content loss or missing controls was
identified. Suspected overlaps, spinner state, unlabeled placeholders, and scroll-viewport
clipping reproduce in the original references and were left outside migration scope.

CI disables parallel simulator testing so the prepared, booted device is the test host,
matching the independent local comparison invocations.

Final checks ran after rebasing to main at `5a48558`. The full updated-main screenshot
comparison also passed 79/79 with `TEST SUCCEEDED`. Package simulator results are in
`/private/tmp/aura-xcode27-updated-main-package-ios.xcresult`. Swift 6.4 reports the host
package run as separate target bundles; all 18 bundle summaries passed (940 unique tests).
The optional `--xunit-output` invocation did not create an XML file for this Swift Testing
run, so host accounting uses the complete console summaries and successful exit status.
No filters or skips were used. The native macOS and generic iOS Simulator app builds ran
serially with four jobs and both completed successfully.

The rebase's only autostash conflict was the status document; both sets of notes were
preserved and the conflict resolved. Autostash `48f289a` remains as a recovery backup.

Candidate CI must use the exact version and runtime rather than the latest installed
ones. The [runner manifest](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
lists the required Xcode and iOS runtime; a successful actual runner execution is still
required before cutover. The [runner is in public preview](https://github.com/actions/runner-images/issues/14404).

## Hosted candidate results

[Migration PR #75](https://github.com/fardavide/Aura/pull/75) is a draft. Candidate `da08916`
ran on the pinned hosted environment in [run 38370317745](https://github.com/fardavide/Aura/actions/runs/38370317745).
Both platform builds and the host package suite passed. All 79 snapshot comparisons passed
on the first attempt, but the runner did not exit before the job timeout; the failed-job-only
retry completed successfully, so all four existing required checks are green.

The added iOS 26.0 job successfully downloaded runtime build `23A343` on a temporary runner.
The first package run passed 566 tests, with two test-bundle startup timeouts. On retry all
880 tests ran: 879 passed, and the existing live-player replacement/deadline test failed
because its model reported a failed stream rather than a loading one. This is not yet a
confirmed production incompatibility: native media callbacks and the test's pending asset
loader need discrimination. The test verdict remains failed; no assertion or gate was relaxed.

The next diagnostic moves app build/install/launch ahead of package testing and runs the
live-player suite alone before the unchanged full suite. A native-item error assertion adds
evidence to the failing test. Verbose simulator diagnostic collection is disabled only for
that focused diagnostic; both its result bundle and the full suite's diagnostics are retained.

Candidate `2ca4511` passed all four existing checks in
[run 38403927282](https://github.com/fardavide/Aura/actions/runs/38403927282), including the
full snapshot suite. Its minimum-runtime job provisioned iOS 26.0, then timed out during
the app build before launch or either package test invocation. GitHub marks the run cancelled;
the job log endpoint returned `BlobNotFound`, so the build's actual stall point is unverified.
The following diagnostic keeps the same build destination and flags, removes quiet output,
and bounds that build step to ten minutes so the job can finalize and retain its logs without
exhausting the overall job timeout. No assertions, tests, tolerances, or gates are relaxed.

The diagnostic candidate is rebased onto merged playback follow-up `a6d5802` from
[PR #76](https://github.com/fardavide/Aura/pull/76). Its only rebase conflict was the status
document; current playback and migration evidence were both preserved. The app is now
0.8.3 (build 67), inherited from main. The full minimum-runtime package suite consequently
includes the twelve new playback tests (892 tests rather than the earlier 880).

Candidate `e0ea9c4` passed host tests and both platform builds in
[run 38472671657](https://github.com/fardavide/Aura/actions/runs/38472671657).
All 79 snapshot tests passed and xcodebuild emitted `TEST SUCCEEDED`; its simulator
diagnostic collection timed out after 600 seconds, pushing job cleanup against the
forty-minute limit and leaving the job cancelled. The snapshot job now has sixty minutes
to retain the existing diagnostic collection and artifact behavior; comparison thresholds,
inventory, and the required job verdict stay unchanged.

The minimum-runtime job downloaded and installed iOS 26.0 (23A343), then hung after
runtime enumeration during simulator creation/boot. It never reached app build, launch,
or package tests. No phase markers existed to distinguish those setup commands, and
the cancelled job retained no native results. Creation, boot, and readiness now emit
phase markers; provisioning is bounded to twenty minutes, preserving time for job cleanup
and logs. The app-build diagnostic's ten-minute limit and verbose output remain in place.

Candidate `05c1067` passed all four original checks in
[run 38515392842](https://github.com/fardavide/Aura/actions/runs/38515392842).
On iOS 26.0, simulator setup, app build, install, and launch succeeded. The focused
live-player suite passed all 25 tests, and its earlier replacement/deadline failure did
not reproduce in the full suite either. The full package result ran all 892 tests:
890 passed, two failed, and none were skipped. All twelve new playback handoff regressions
passed on the minimum runtime.

The failures were existing fast-forward tests for retaining the media item when changing
4× to 8× and skipping backward across empty recording windows. Both used a fixed count of
`Task.yield()` calls instead of observing native load completion. The first failed its ready
precondition after 0.309 seconds; the second proceeded with a backward skip before verifying
that its fast-forward composition had loaded and searched toward the span's lower bound.
The next candidate repairs only those test preconditions with observation of loading
completion and a bounded test deadline. Existing behavior assertions, fixtures, production
code, snapshots, and comparison thresholds remain unchanged; an unexpected failed or
empty terminal state still fails the ready-composition precondition. Native CI must confirm
this diagnosis before minimum-runtime validation is accepted.

The test-only candidate passes all fourteen fast-forward acceptance tests and the full
host package suite. A fresh review confirmed the existing assertions are preserved,
the backward-skip given state now explicitly requires a native composition, and the
observation API is available on iOS 26. The speed-selection action synchronously publishes
loading before starting its media task; observation therefore cannot accept the previous
ready player. The one-minute test limit still records a failure and cancels a stalled wait.

Native bundles are retained locally at
`/private/tmp/aura-xcode27-ci-ios26-05c/MinimumIosPackageResults.xcresult` and
`/private/tmp/aura-xcode27-ci-ios26-05c/MinimumIosLiveDiagnostic.xcresult`.

Candidate `61ddd0f` passed all four original checks in
[run 38531721273](https://github.com/fardavide/Aura/actions/runs/38531721273),
including all 79 snapshot tests in eleven suites. Two independent minimum-runtime
attempts installed iOS 26.0 (23A343), created and requested boot of the simulator,
then stalled in `simctl bootstatus` until the unchanged twenty-minute provisioning
deadline. Neither attempt reached app execution or the repaired recording tests.
Both used runner image `xcode-27-arm64` version `20261006.0244.1`, the same version
as the earlier candidate that executed all 892 native tests; image-version drift
does not explain these particular attempts. The underlying startup cause remains
unverified, and minimum-runtime acceptance remains open.

The next candidate retains read-only process inventory, CoreSimulator system logs,
and native simulator diagnostics after a provisioning failure. Each probe has a
sixty-second deadline and the failure-only collection step is bounded to five
minutes. Partial output and explicit timeouts remain available even if a service
probe stalls. Native result bundles and this startup evidence share the existing
always-uploaded diagnostic artifact; startup collection does not change the boot
readiness requirement, test scope, comparison thresholds, or original failure verdict.
The new collector regression failed before implementation and the full six-test
CI script suite passes after implementation.

Candidate `a951c14` passed all four original checks in
[run 38609264153](https://github.com/fardavide/Aura/actions/runs/38609264153).
Minimum-runtime startup again reached the twenty-minute deadline. Its retained process
inventory includes the iOS 26 SpringBoard process while the boot-status client remains
pending; the system log and process evidence are available in the diagnostic artifact.
The native diagnostic command received EOF at its Enter prompt and exited without
creating an archive. The next candidate sends one confirmation line to the read-only
probes, with the existing subprocess and step deadlines preserved. An independently
authored child-process regression failed with missing confirmation before this change;
all seven CI script tests pass after it. The retained logs do not establish the underlying
readiness stall, and minimum-runtime acceptance remains open.

The downloaded startup evidence is at
`/private/tmp/aura-xcode27-startup-a951/MinimumIosSimulatorDiagnostics`.

Candidate `cc074c1` passed both app builds and host package tests in
[run 38681529553](https://github.com/fardavide/Aura/actions/runs/38681529553).
The snapshot runner lost communication with GitHub during its test step; GitHub retained
no job log or snapshot result for that attempt. This is an infrastructure failure, not
evidence of either passing or failing image comparisons.

The iOS 26 setup again reached its twenty-minute readiness deadline. Confirmation now
allows native diagnostics to retain partial device, display, service, and cache information
under `/private/tmp/aura-xcode27-startup-cc074/MinimumIosSimulatorDiagnostics`.
The device reports Booted and has connected displays, while boot readiness remains pending.
Cache and service warnings alone do not establish the cause; the native collector itself
also reached its internal thirty-second deadline and retained partial output.

The next controlled experiment uses the documented single `simctl bootstatus -b -d`
operation to boot and await readiness, with migration details enabled. It replaces the
separate boot request followed by monitoring. The readiness requirement, twenty-minute
deadline, full native suite, and all snapshot gates remain unchanged. The independently
authored startup regression failed with six operations instead of five before this change;
all seven CI script tests now pass. CI must establish whether this sequence affects the
observed stall; minimum-runtime acceptance remains open.

## Rollback contract

Roll back the runner label, Xcode selector, simulator pin, corresponding PNG references,
and environment guidance together through a reviewed PR. A toolchain-only rollback
with iOS 27 images would recreate the mismatch. Keep all four existing required checks.
