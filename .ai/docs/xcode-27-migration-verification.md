# Xcode 27 migration verification

Local implementation is authorized; commit, push, PR publication, merge, archive settings,
and developer-machine configuration remain separate approvals. The migration worktree is
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
This machine has no iOS 26 runtime. Verification on the minimum iOS version and native
macOS 26.5 remains pending an approved environment provision. Xcode Cloud stays
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
| iOS 26 runtime compatibility | Pending environment approval |
| Native candidate CI | Pending publication approval |

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

## Rollback contract

Roll back the runner label, Xcode selector, simulator pin, corresponding PNG references,
and environment guidance together through a reviewed PR. A toolchain-only rollback
with iOS 27 images would recreate the mismatch. Keep all four existing required checks.
