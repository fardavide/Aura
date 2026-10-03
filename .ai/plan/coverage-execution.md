# Aura coverage execution adaptation

Status: Davide approved trying this policy and subsequently chose Granita's fixed package-first
mapping convention for the cross-platform Total. Implementation and local acceptance are complete;
numerical baseline approval, CI validation, publication and merge remain pending. Snapshot images,
tolerances and reusable skills are unchanged.

## Starting point

Fetched `origin/main`: `15cf8cc098e27c12e753d42275b7b2723a241fd7`.
The initially detached checkout matched this revision and was clean. Work branch:
`ci/coverage-artifacts`, created from that fetched default branch.

Rebased without conflicts on 2026-10-02 onto fetched `origin/main`
`3fa3b066bacd503bdda83bc703f94e52d744c92b`, after
[Aura PR #72](https://github.com/fardavide/Aura/pull/72) merged. Fresh validation uses this
revision because it changed Settings tests and snapshot references. Fetch and rebase again
before committing or merging.

References read:

- Codex discussion “Improve coverage check”, local thread
  `01a0ec9f-7d45-7d10-94b4-a827aac030b0`.
- Codex implementation “Optimize Granita CI Coverage”, local thread
  `01a0f2e8-caf9-7741-bb9d-d5c1a380d014`.
- [Merged Granita implementation](https://github.com/fardavide/granita/pull/120),
  merge revision `88362b05a462c2cdf26a22f8619046dc2c52dd40`.

Aura currently has no numerical coverage workflow, summary, baseline or ratchet. Its four
required verdicts are `Unit tests (AuraKit)`, `Snapshot tests (iOS)`, `Build app (iOS)` and
`Build app (macOS)`. The active GitHub `protect-main` ruleset was read and confirms these
exact four required contexts, strict up-to-date checks and pull-request-only squash merging.
It does not require Coverage yet. No repository setting was changed.

The package verdict is `swift test` inside `AuraKit/`. The shared package scheme is
`AuraKitTests`, also run from the package container when Xcode is needed. The root app
scheme `Aura` contains only `AuraTests`: it must never stand in for package testing.
The app-hosted suite includes screenshot comparisons, four asset-colour assertions and the
existing example test. Preserve all of them. Native macOS remains a compile gate; its
offscreen renderer cannot faithfully capture glass, so no macOS snapshot collection is proposed.

## Approved trial measurement policy

Measure LLVM executable **lines and regions**, with covered and total counts retained per file.
Use these three rows, independently gated:

| Row | Counters from | Exact production source scope |
|---|---|---|
| Package | Required AuraKit host test execution | `AuraKit/Sources/**/*.swift` |
| App-hosted iOS | All required AuraTests, including colours and screenshots | `AuraKit/Sources/**/*.swift` plus `Aura/**/*.swift` |
| Total | Both raw profiles, exported with package mappings first, then iOS mappings | `AuraKit/Sources/**/*.swift` plus `Aura/**/*.swift` |

Paths are resolved relative to the recorded source root, not by matching an arbitrary substring
anywhere in a dependency path. Every production module's mapping inventory must be accounted for;
an unlinked or missing mapping cannot silently shrink the denominator. Files containing no
executable regions are reported separately from missing files. Resources are not executable Swift.

Only sources outside those explicit roots are excluded: package/app tests, shared test doubles,
generated build files and dependencies. Within the production roots, include views, view models,
platform adapters, composition code and action closures. Do not import Granita's special
host-reachability or view-action exclusions, its server modules, its TLS taxonomy or its macOS
snapshot category. Platform-conditional code is measured using the code compiled on each actual
platform: the package row is macOS-host code and the app-hosted row is iOS code. Total merges
all raw counters but retains the package mapping for overlapping function/source identities,
matching Granita's existing ordering. This is the `aura-production-host-first-union-v1` contract,
not a promise to retain every alternate platform region in one row. The independently gated
iOS category retains all iOS regions. Report this limitation explicitly; compile gates supply
no execution counters. Changes to precedence require a new scope and reviewed baseline.

Required new verdict: **Coverage**. Require all four existing verdicts to succeed and enforce
all six line/region ratios (Package, App-hosted iOS, Total). Propose a percentage ratchet with
no fixed floor and **zero permitted regression**; compare integer ratios exactly, without rounded
display values or hidden epsilon. No category can compensate for another. This is a new Aura
policy approved for this trial, not a claim that Aura already had Granita's ratchets. Granita's existing
script allows 0.05 percentage points and skips uncomparable baselines; neither behavior is
silently adopted here. Missing categories, zero denominators, invalid/changed scope identities
and missing or incompatible baselines must fail rather than emit a skipped passing check.

### Initial baseline and later ratchets

1. Freeze one fetched default-branch application revision, Xcode build, Swift/LLVM versions,
   host architecture, SDKs, simulator runtime and instrumentation configuration. Existing runs
   without counters cannot provide a numerical baseline.
2. On that same application source and toolchain, run the old uninstrumented required paths to
   retain their test verdict and inventory evidence; collect an independent instrumented direct
   reference without sharding. Compare it with the new artifact collection/aggregation path.
   These deliberate acceptance runs are separate from normal required CI execution.
3. Compare per-file and per-category covered counts, denominators, mappings, inventory and six
   verdicts. Repeat cold, warm and fresh-counter executions. Investigate all differences; retain
   the measurements and explanation. Do not alter exclusions, pixels, tolerances or baselines
   to conceal a discrepancy. A repeatable baseline is a prerequisite to activating the ratchets.
4. Present the measured default-branch seed summary and its provenance for review. Commit the
   reviewed seed so the introducing change has a concrete baseline instead of an ungated bootstrap.
   Record explicitly that it is the one-time initial seed; do not invent a 90%/100% floor.
5. After activation, compare against the newest fully successful default-branch push run with
   the agreed scope/toolchain contract. Publish its compact summary as an immutable run artifact,
   with enough provenance for local retrieval. A PR or failed/incomplete main run never advances
   the baseline. Use the approved seed only during the explicitly bounded first introduction;
   it is not a fallback to an older floor when a later main artifact is missing or expires.
6. Require the approved baseline on local and CI commands. Missing, expired, incompatible or
   partial baselines fail with an actionable diagnostic. Changing scope/toolchain compatibility
   or reseeding is a separate reviewed policy decision.
7. Keep GitHub required-check activation explicit. Publication, baseline review, changes to
   repository rules and merge retain the existing approval boundaries.

## Proposed execution structure

The package job runs every existing package test once with coverage enabled, through SwiftPM
inside `AuraKit/`, retaining its original concurrency and verdict. It records an independently
enumerated inventory plus completed identities and argument cases, rather than trusting only
a positive test count. Clear counters before every collection. Reuse compatible compiled
products, keyed by actual source/configuration/toolchain inputs, never cached counters.

The iOS build verdict can produce instrumented `build-for-testing` products once, with bounded
build jobs and unchanged unsigned compile verification. Distribute an archive of products and
matching mappings with a verified build stamp, preserving modes and symlinks and excluding
profiles. Retain the existing macOS compile job. An iOS archive must match the checkout revision,
run attempt, source fingerprint, root/path contract, toolchain, SDK/runtime and build options.

Evaluate two isolated iOS snapshot runners with whole-suite assignment; keep a stable aggregate
`Snapshot tests (iOS)` verdict requiring every shard. Preserve the full matrix and all colour
assertions. Avoid concurrent window rendering inside a process. Aura presently lacks explicit
serialized traits and its observed suite intervals overlap. Granita's implementation session
clarified that its verified combination had nonparallel testables, an xctestrun with
`InProcessParallelizationEnabled = false`, serialized suites and the CLI parallel-testing
flag disabled. It did not isolate the effect of that CLI flag alone. Verify Aura's resulting
xctestrun settings and actual suite/test start-to-pass overlap before accepting serialization;
neither MainActor nor a trait on unrelated top-level suites is sufficient evidence by itself.
Do not copy overlapping suite wall times as serial
weights. Measure isolated/unsharded serialized workloads, balance them, and retain sharding only
if the same-revision comparison preserves every method, argument and image case exactly once
and improves elapsed time at an understood runner cost. No in-process parallelism is proposed.

Each collector emits fresh unfiltered profiles plus every matching coverage binary/object,
source revision and source-content fingerprint, actual compiler/LLVM/Xcode/SDK identity,
architecture/platform, run ID and attempt (unique local collection identity outside CI), suite
and configuration, planned and completed inventories, successful completion receipt, build
stamp and SHA-256 file inventory. A complete manifest is created only after the command succeeds
and all expected cases pass. Failed collections retain logs/result bundles and image reports,
but never produce successful artifacts. Require exact inventory and absence of duplicates,
skips, failures and unplanned cases.

Coverage downloads those artifacts, requires all upstream verdicts, validates every manifest,
file and inventory before any arithmetic, merges unfiltered profiles with `llvm-profdata`,
exports with all matching mappings via `llvm-cov`, renders category/total reports and enforces
the approved six ratchets. No builds, tests, simulator boot or rendering belong in Coverage.
Never combine percentages or filtered summary JSON to produce Total. Reject incompatible,
stale, corrupt, missing, extra or partial artifacts and mapping warnings. Prove duplicate shard
mappings do not change exported denominators. Granita's session also verified that its retained
profiles have empty LLVM binary-ID lists: `--check-binary-ids` alone cannot certify compatibility.
Require the source/build provenance, hashes, mapping inventory and controlled measurement
comparisons as well. Its cross-platform proof preserved an existing legacy measurement; Aura's
new baseline additionally needs explicit inspection of its actual conditional-platform mappings.
Preserve raw exports for diagnosing regressions.

Add a sanctioned `make coverage` command that runs the same collectors, inventory validators,
aggregator and gate against the same approved baseline. Its local session identity prevents
mixing profiles from separate executions. Provide separate collection/report/tooling-test
targets for focused validation. Keep simulator discovery out of host/report-only targets.
No automatic external comments are needed to make the report reviewable.

## Inspected inventory

Current source: 79 app-hosted test methods in 11 suites. Nine rendering suites have 74 screen
states and **592 PNG references**, one for each phone/tablet × orientation × theme configuration.
The other methods are four colour assertions and the existing example. These counts match the
latest successful CI receipt; they are observations, not hard-coded future ceilings.

| Rendering suite | Methods | Reference images |
|---|---:|---:|
| Camera grid | 8 | 64 |
| Camera detail | 5 | 40 |
| Events list | 7 | 56 |
| Event detail | 5 | 40 |
| Exports list | 8 | 64 |
| Export editor | 10 | 80 |
| Recording player | 11 | 88 |
| Settings | 12 | 96 |
| Timeline screen | 8 | 64 |

The latest successful package receipt reports **936 tests in 128 suites**. The package manifest
defines 19 test targets. Snapshot comparison remains `precision = 0.98` and
`perceptualPrecision = 0.87`; images and capture configuration remain unchanged.

## Existing CI timing evidence

These are historical different-source runs, not the same-revision equivalence experiment.
Elapsed time is run creation to completion; runner time sums job start-to-completion intervals
and excludes queues. Per-job queue intervals can overlap and are not added to elapsed time.

| Successful run | CI elapsed | Total runner | Snapshot step | Package step | iOS build | macOS build |
|---|---:|---:|---:|---:|---:|---:|
| [Latest inspected](https://github.com/fardavide/Aura/actions/runs/36932665327), `be725058` | 32m44s | 48m33s | 29m12s | 1m55s | 2m35s | 2m21s |
| [Prior inspected](https://github.com/fardavide/Aura/actions/runs/36309228828), `81d14c8e` | 27m18s | 40m30s | 24m13s | 1m36s | 2m38s | 2m38s |

The subsequent successful [frozen-main run](https://github.com/fardavide/Aura/actions/runs/36945893103)
uses `3fa3b066bacd503bdda83bc703f94e52d744c92b`, the current acceptance application's source.
Its elapsed time is 30m23s and occupied runner time sums to 43m58s. The original snapshot step is
27m13s; package execution 1m36s, iOS compilation 2m37s and macOS compilation 2m43s. The macOS
job waited 4m21s after run creation; the other jobs started after 8–11s. These are the same-source
old-path reference, not measurements of the new distributed CI path.

Latest snapshot job: 32m32s runner time; initial queue 11s; checkout 2m40s; source-cache restore
5s; resolve 21s; simulator availability check 2s. Swift Testing reports 1382.042s (23m02s)
for all 79 cases, while Xcode reports 1665.712s for its testing operation. The complete snapshot
step is 1752s. These intervals nest; do not sum them. Compilation, test-host/simulator startup
and teardown explain separate intervals that must be measured, not attributed to rendering
without evidence. The four job initial waits sum to 62s; no successful-run coverage artifact
transfer exists yet. Checkout alone costs 144–211s across the latest jobs.

The rendering suites start together and their reported completion durations range from 949s
to 1382s; these overlap and cannot be added or used as isolated work weights. Sharding merits
a controlled benchmark, rather than copying Granita's two-shard weights.

The fetched main push [run](https://github.com/fardavide/Aura/actions/runs/36936302772) was queued
at initial inspection and was in progress on the subsequent check. Do not treat it as completed
or use it as a seed without live verification.
CI selected Xcode 26.6; the local installed Xcode is 27.0 (27A266a). No system toolchain setting
was changed. Local tooling tests can run here, but numerical/rendering equivalence with CI
requires one deliberately controlled toolchain; Xcode 27 local runs cannot establish Xcode 26.6
CI equivalence. CI publication will therefore remain a concrete later approval step.

## Acceptance evidence

Local Xcode 27 / iOS 26.5 evidence on the original revision included package execution,
iOS and macOS compilation, all 79 app-hosted methods and 592 image comparisons. The raw
iOS export contained 243 executable production files; the source receipt retained all 293
production files, including protocol-only files without executable regions. This evidence
does not establish Xcode 26.6 CI equivalence.

After the rebase, the required package collector passed all 937 independently enumerated
methods and 30 parameter cases across 19 targets. It emitted a complete, hashed artifact with
the current revision and local run identity. The instrumented iOS build succeeded. The fresh
full iOS run reported all 79 methods passed in 299.838 seconds. Its native process completed
successfully in 909.319 seconds, including a 600-second diagnostic timeout after the tests.
Its receipt and hashed collection artifact were accepted. Both platform compile checks passed.

Artifact, inventory, products, baseline and aggregation tests cover fail-closed behavior.
Coverage reports retain exact collection identity, per-file counts and HTML ratchet verdicts;
candidate reports explicitly have no verdict. No initial numerical seed has been fabricated.
The sanctioned fast tooling command passed 448 tests on 2026-10-02. Eight workflow contracts
cover collection once, product reuse, isolated runners, complete snapshot verdict, aggregation
without native execution, unevaluated candidates and pinned tooling tests. The workflow is a
local draft: its mapping scope is settled; numerical bootstrap and CI validation remain pending.
The latest fetch still matches the rebased HEAD with zero commits ahead or behind. Production
Swift, all existing test Swift, snapshot images, tolerances and the project target graph have
no changes relative to that fetched default branch. Nothing has been published or merged.

### Cross-platform mapping precedence found during acceptance

The rebased full-run raw profile and identical object bytes produce different Total measurements
when only the order of iOS and macOS coverage mappings changes:

| Mapping order | Covered / executable lines | Covered / executable regions |
|---|---:|---:|
| Package host first | 15,235 / 18,065 | 4,286 / 5,341 |
| App-hosted iOS first | 15,266 / 18,109 | 4,297 / 5,361 |

For the platform-dependent icon switcher, iOS has 12 executable regions, while a host-first
Total contains only 4. This is not a profile-transfer or percentage arithmetic problem: the
same merged raw profile, same toolchain, same source and same binaries were used. LLVM emitted
no warning. Explicit `--unify-instantiations` did not remove the order dependence. This initially
blocked a Total promised as a complete mapping union. Davide's later Granita choice superseded
that contract with explicitly fixed host-first precedence. The [LLVM loader](https://github.com/llvm/llvm-project/blob/main/llvm/lib/ProfileData/Coverage/CoverageMapping.cpp)
deduplicates by function/source identity, retaining the first mapping even when region geometry
differs. Source/toolchain provenance alone therefore does not imply a complete platform union.

Davide chose “Do the same as Granita” after reviewing its cross-platform fixed-order aggregation.
Aura retains host package execution, iOS-only snapshots and both platform compile gates. LLVM's
loader deduplicates records by function/source identity and retains the first, explaining the
overlap behavior. Evaluated Total always loads package mappings before iOS mappings, regardless
of artifact listing order. Reversed Total exports remain diagnostic evidence, not ratchet values.
Independent categories still reject order-dependent mapping measurements. No numerical baseline
has been approved or required-check setting changed. CI validation remains pending.

The first isolated iOS shard passed in 149.035 seconds and the second in 182.808 seconds, reusing
the same instrumented products. Both retained their native success verdicts; together they completed
all 79 cases exactly once. Their raw merged export matches the full unsharded export exactly for
every production file in each category. This equality also holds for the order-dependent Total,
which was initially rejected before Davide chose Granita's fixed-order convention. Its accepted
host-first measurement now has an explicit scope identity; reversed exports remain diagnostic.
Product archive and restoration validation succeeded, with exact bytes and no cached counters.
These ran sequentially
on one Mac, so their maximum is a potential parallel execution interval, not observed CI wall time.
The full unsharded native operation was 909.319 seconds, including a 600-second simulator
diagnostics timeout after all 79 methods passed in 299.838 seconds. Keep that overhead visible;
do not disable diagnostics to disguise it or attribute the entire gain to rendering.

### Fresh-counter repetition after the final local execution contract

The fresh collection `local:8bdcaf34-c18a-4637-ae9e-ac6cf65c8b5d` on the same application revision
passed all 937 package methods and 30 argument cases. Reused instrumented iOS products passed
all 40 first-shard cases in 143.399s (native operation 154.470s) and all 39 second-shard cases in
159.249s (native operation 183.030s). Both fresh simulators were independently created and removed.
The complete snapshot inventory remained 79 methods and 592 existing image comparisons.

Every file's lines and regions in all three scopes exactly matches the retained full-run reference:
Package 5,561/17,271 lines and 2,175/5,216 regions; iOS 12,391/18,054 and 3,161/5,345; fixed host-first
Total 15,235/18,065 and 4,286/5,341. The same report command passed all six exact ratchets against
the retained local acceptance reference. That reference is explicitly local-only and is not an
approved numerical CI seed. Current reports retain all 50 audited unmapped production files
alongside the 240 package or 243 app/Total mapped files.

The latest macOS compile command and its immediate warm verification both exited successfully.
The first emitted transient compiler task diagnostics stating a command exited 0 without output;
the warm repeat completed cleanly. No production source was changed to alter that result.

One earlier warm package attempt crashed with SIG5 in the existing Timeline test's array access.
It emitted no successful manifest and is preserved under `build/coverage-validation/package-warm-crash`.
Subsequent required collectors passed, preserving the original package concurrency. The cause has
not been claimed beyond the recorded crash frames; no test, tolerance or verdict was relaxed.

Initial candidate source verification now checks actual Git tree/blob bytes from both the frozen
main revision and collection commit against the checkout, retaining separate revision fields.
Tree objects, source differences masked by dirty files, protected symlinks and export-ignore
omissions are rejected. Only the app scheme's serial setting is normalized. A candidate's native
runtime/build identity remains in the candidate, approved baseline and final report, and changed
runtime versions/builds fail before LLVM aggregation. Candidate dispatch transfers the frozen SHA
through an environment variable rather than interpolating it directly into shell commands.

### Isolated cold compilation and complete execution

An empty package scratch directory compiled and passed the complete host suite. Independent native
enumeration and event verification retained all 937 methods, 967 method/argument receipts and 19
mapping binaries. A fresh raw-profile merge and export matched the warm package counters per file.
An empty iOS derived-data directory compiled instrumented products, then a fresh simulator ran the
full unsharded inventory: all 79 methods passed in 305.312s, native operation 330.511s. The collector
emitted a complete, hashed artifact; its runtime/build/source identity matched the warm run.

Cold iOS exports and the cold host-first Total raw-profile merge exactly matched the warm shards
and retained full-run references per file. No counts, denominators or verdicts changed. The direct
cold acceptance runs are deliberate verification experiments, not additional required CI execution.
The uncompressed payloads currently occupy 73 MiB for package coverage and 159–160 MiB per iOS
coverage shard; iOS compiled products occupy 180 MiB. CI compression and transfer durations remain
to be measured, so these sizes are not a claimed network duration or performance gain.

The actual sanctioned `make coverage` command failed before collection with the expected missing
approved-initial-baseline diagnostic tied to frozen main `3fa3b066bacd503bdda83bc703f94e52d744c92b`.
It did not rerun tests or mutate retained collection evidence. The common report command passed all
six gates against the explicit local acceptance reference, demonstrating the evaluated verdict path.

- RED/GREEN tests for artifact rejection, inventory completeness, raw aggregation and six gates.
- Existing host package test verdict and iOS/macOS compile verdicts.
- Complete app-hosted inventory and all 592 current image comparisons, with unchanged tolerances.
- Same-source/toolchain direct-reference versus artifact/sharded exports, including per-file counts.
- Cold, warm and fresh-counter repeated results; investigate coverage nondeterminism explicitly.
- Rejection of every malformed, failed, stale, incomplete or incompatible input and baseline.
- Benchmark wall time, total runner time, dependency waits, simulator startup, compile/render/export,
  cache/product transport and coverage artifact transfer separately; include validation-only cost.
- Exact proposed publication text before publishing, and separate approval for merging.

### First CI portability corrections

Branch commit `9e9440e9f1336f70dd9bb1adf722450e484317a1` was dispatched in
[run 36990855600](https://github.com/fardavide/Aura/actions/runs/36990855600), using frozen
application reference `3fa3b066bacd503bdda83bc703f94e52d744c92b`. Package tests and macOS compilation
passed. Ubuntu Python 3.12 rejected two test-class annotations during collection; postponed
annotations correct that portability issue without changing their tests. iOS compilation finished,
then source validation rejected the false path `TestDoubles/Fake/AppIconSwitcher.swift`.
Xcode's common source prefix can end inside a filename: concatenation reconstructs the actual
`TestDoubles/FakeAppIconSwitcher.swift`. The installed Xcode `xcodebuild.xctestrun(5)` manual
documents this text-prefix contract. A regression reproduces the native CI prefix, and validation
of the retained local Xcode plan accepts all 339 source inputs and 293 production files.

A real shallow-clone regression verifies retrieval of the exact frozen reference after follow-up
commits, while preserving collection HEAD, refs and working-tree state. Candidate preflight now
fetches only a missing reference SHA and verifies protected application inputs before downloading
coverage artifacts. Local tooling verification passes 451 tests, with three native experiments
deselected; the initial failed run is acceptance cost, not a successful performance measurement.

## Native CI candidate and retry investigation

[Run 37001257836](https://github.com/fardavide/Aura/actions/runs/37001257836) passed the four original
required checks, both isolated snapshot jobs, all 451 tooling tests and candidate aggregation.
Coverage correctly failed solely on the absent approved numerical seed. The unevaluated candidate
retains actual collection `cd912fee370c6594e6dcec0b933d06546d0fca95`, frozen application revision
`3fa3b066bacd503bdda83bc703f94e52d744c92b`, all 1,095 protected files, Xcode 26.6/17F113, Swift
6.3.3, LLVM 21 and iOS 26.5/23F77. Mapped/unmapped inventories match local acceptance. These are
CI candidate measurements, not an approved seed or a passing ratchet verdict:

| Scope | Covered / total lines | Covered / total regions |
|---|---:|---:|
| Package | 5,562 / 17,296 | 2,177 / 5,241 |
| iOS | 12,411 / 18,085 | 3,181 / 5,376 |
| Fixed host-first Total | 15,255 / 18,096 | 4,307 / 5,372 |

The trial took 45m38s elapsed and 79m32s total runner time, including the extra bootstrap Coverage
and candidate jobs. Frozen main took 30m23s and 43m58s respectively. This is not a speed improvement.
The native 40- and 39-method shards passed in 526.380s and 662.350s; the old full native run took
1,247.628s. Each shard additionally repeated native discovery before case execution (approximately
4m16s and 7m49s). Candidate source verification took 217s twice; the full inventory includes 2.1 GiB
of snapshot PNGs, and the original verifier retained Git and working-tree copies simultaneously.
Checkouts cost 110–172s per job. Product archiving cost 38s; per-artifact upload/download steps cost
1–8s. Queues and dependency waits are retained in raw job metadata under `build/coverage-validation`.

The retry streams byte comparison against authoritative Git blobs, verifies collection tree object
identity against frozen main, and preserves the exact canonical digest. A 16 MiB regression reduced
peak allocation below 8 MiB; the full 1,095-file local proof used under 3 MiB in 9.352s. Native
inventory discovery now runs once with the instrumented build and travels with sealed products.
Consumers reject corrupt, missing, incompatible, symlinked or failed inventories before execution.
Discovery counters are excluded from distribution. Local producer discovery verified all 79 methods
in 24.892s. Suite weights now come from the complete validated CI case union, with provenance.
The tooling suite passes 464 tests. Both optimized native shards passed (39 methods in 136.512s,
40 methods in 162.628s), emitted valid manifests and passed the exact 79-method union check.
Fresh package collection passed with the same collection identity. Comparison against the retained
Xcode 27 local reference passed five ratchets but failed the iOS line ratchet: 12,390 / 18,054
instead of 12,391 / 18,054. Package and fixed Total measurements remain identical per file;
iOS differs only in `DefaultSettingsRepository` (39 / 148 lines instead of 40 / 148).
Region counts and all denominators agree. Full native LLVM line evidence identifies line 72,
the persisted dynamic-camera-order read; theme/dynamic-order branch counters also differ.
Artifacts and the failed verdict are preserved under `build/coverage-validation/retry-local-v2`.
The source/compiler/runtime agree. Discovery's possible app-state effect remains a hypothesis:
isolated discovery returned all methods but left the simulator shut down; app-container lookup
failed specifically because the device was shut down. This does not prove an app-state change.
Neither a seed nor an exclusion was changed to conceal this difference. Native CI retry and the
cause of this local measurement difference remain pending.

## Reusable rules pending Aura validation

Keep global kickstart and related skills unchanged until Davide confirms this adaptation works.
Candidate rules: inspect actual required taxonomy and approve absent coverage policy first;
collect once during required executions; validate provenance, receipts and exact inventory;
merge raw counters with matching mappings; never cache counters; isolate shared renderers;
measure startup/checkout/transfer alongside execution; distinguish elapsed time and runner cost;
keep local/CI measurement and failure semantics identical; require explicit baseline seeding
and never silently skip a missing comparison. Preserve project-specific scopes and platform
decisions rather than transplanting another application's names or exclusions.
Also inspect overlapping mappings: LLVM can silently retain only the first platform's regions.
Preserve and name an existing fixed mapping precedence when retaining legacy measurements;
require order invariance when a policy promises a complete platform mapping union. Validate source-root compatibility
before distributing app-hosted products: compile-time snapshot paths can make a relocated checkout
unsafe even when LLVM's exported source paths can be normalized. Keep preserved diagnostics and
previous runs when preparing fresh local counters and collection destinations.
