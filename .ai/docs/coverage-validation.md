# Coverage collection and acceptance

Aura collects coverage during its required host AuraKit tests and app-hosted iOS snapshot tests.
The package command runs inside `AuraKit/`; the app scheme does not contain package tests.
Both iOS and macOS compilation remain required. macOS snapshots remain intentionally excluded.

The iOS build produces instrumented products and independently discovers the complete native
test inventory once. The inventory travels with its matching build stamp and checksum in the
compiled-product archive. Shards validate and consume that inventory without rediscovering tests.
Discovery counters are cleared before distribution and again before each collection.
Native discovery also initializes the host app's persisted preferences. Each consumer therefore
launches the matching compiled host once, waits for its real initial settings, and restores the
simulator's prior state before clearing counters and executing cases. This preserves the original
collection state without rediscovering tests or manually writing preferences. Preparation errors
retain native command diagnostics and fail before any successful collection can be sealed.
Two isolated runners execute disjoint whole
suites with serialization within each process. The stable snapshot check validates every native
receipt and requires the complete independently enumerated inventory exactly once. The coverage
job validates and aggregates artifacts; it never builds, tests, boots a simulator or renders images.

## Measurement and comparison

Three scopes retain executable line and region counts, with per-file measurements:

- `aurakit-production-host-v1`: all production Swift under `AuraKit/Sources`, measured on the host.
- `aura-production-ios-v1`: production Swift under `AuraKit/Sources` and `Aura`, measured on iOS.
- `aura-production-host-first-union-v1`: the raw-profile merge, exported with host package mappings
  first and iOS mappings afterward, following Granita's convention.

LLVM retains the first overlapping function/source mapping. Total therefore has a fixed mapping
precedence rather than every alternative platform region; the independent iOS row retains its
iOS geometry. Reversed Total exports are diagnostic evidence. Ratchets always use the documented
order. Changing it requires a new scope and a reviewed baseline.

Each scope has separate line and region ratchets: six exact integer-ratio comparisons with zero
permitted regression and no fixed floor. No category compensates for another. Collection identity
includes the actual revision, source fingerprint, toolchain, architecture, configuration and run
attempt. Native runtime identity, completion receipts, independently enumerated inventories,
matching objects and SHA-256 payload inventories must agree before any raw profile is merged.
Missing, failed, stale, incomplete, corrupt or incompatible inputs fail the gate.

The full production source inventory must equal mapped files plus reviewed unmapped files.
`.github/coverage/unmapped-sources.json` records each unmapped file's exact hash, applicable scopes
and reason. This classifies files without file-attributed LLVM regions; it does not remove counters
from a mapping. Unknown files, changed classified contents, or a classification that gains a mapping
require investigation and fail collection. Toolchain changes may require a newly reviewed inventory.

## Local command

`make coverage` retrieves the approved baseline first, preserves previous owned collection outputs,
initializes a fresh identity, collects package and both iOS shards sequentially, verifies macOS
compilation, and runs the same aggregation/verdict code as CI. Compatible build products are reused;
counters are cleared before collection and excluded from product archives and build caches.
The default local paths are under `build/`; previous diagnostics move into `build/coverage-history`.

`make coverage-tests PYTHON=.venv-coverage/bin/python` runs the pinned Python tooling suite.
Individual collection, product-transfer and reporting targets support acceptance experiments.
`make coverage-candidate` produces explicitly unevaluated measurements, never a passing coverage
verdict or a comparison baseline.

## Initial numerical baseline

Aura had no coverage gate or numerical baseline before this change. An initial seed needs explicit
review and the CI toolchain; local Xcode 27 measurements cannot seed Xcode 26.6 CI.

1. Freeze the newest fully successful main commit and retain its original required verdicts,
   inventory and job/step timings. Re-fetch and rebase before publication.
2. Run the instrumentation branch on the same application/test source and CI toolchain. The
   manual candidate input supplies the full frozen main commit SHA. Candidate source verification
   compares all protected production, package, test, fixture, snapshot, target, pin and shared-scheme
   inputs in the branch commit and checkout against that frozen reference. Only the app scheme's
   serialization setting is normalized. Tooling/workflow/documentation changes remain distinct.
3. Retain both actual collection revision and frozen application revision in `application_reference`;
   never relabel branch artifacts as main artifacts. A candidate retains `passed: null` and no ratchets.
   Required Coverage still fails if no approved comparison exists during the bootstrap experiment.
4. Compare direct unsharded and distributed collection on identical application source/toolchain,
   including every covered count, denominator, per-file mapping, native case and six verdicts.
   Repeat cold, warm and fresh-counter collection. Investigate all differences before accepting a seed.
5. Review the candidate and its source proof, then approve a one-time initial seed tied to the frozen
   successful main revision. No seed is created automatically. Require the resulting Coverage and
   tooling checks explicitly before merging the ready implementation.

After introduction, the newest fully successful main push supplies an immutable coverage-baseline
artifact. PRs and failed runs cannot advance it. Missing or expired artifacts cannot fall back to an
older seed. Scope/toolchain/runtime changes and reseeding require review.

## Evidence and remaining acceptance

The working evidence and exact measurements are in [the execution record](../plan/coverage-execution.md).
Initial local comparison on `3fa3b066bacd503bdda83bc703f94e52d744c92b` found identical per-file
measurements between a full iOS execution and the two complete shards. All 937 package methods,
30 parameter cases, 79 app-hosted methods and 592 existing snapshot references are retained.
Tolerances, production Swift, test Swift, snapshots and the target graph are unchanged.

Subsequent isolated cold package and iOS builds/executions and fresh-counter warm repetition
retained identical per-file measurements in all three scopes. All six local reference verdicts and
the original 448 tooling tests passed. Subsequent CI portability and inventory-handoff checks
bring the tooling suite to 476 passing tests. Isolated consumers explicitly resolve pinned snapshot
dependency sources into the producer's SourcePackages location before collection; compiled products
alone do not include those xctestrun inputs. The first inventory-sharing retry lost one iOS line:
moving discovery also removed its per-consumer host initialization. Restoring real app preparation
before clearing counters recovered exact per-file equality in all three scopes and all six reference
ratchets, without seeding settings or changing exclusions. The successful corrected Xcode 26.6 CI
candidate matches every per-file measurement from the earlier successful CI candidate, but took
37m17s elapsed and 74m41s runner time, exceeding frozen main. The next trial retains owned simulator
readiness through initialization and collection; local equality and all six reference verdicts pass,
and CI timing remains pending. The failed attempts and native causal evidence remain in the execution
record. The actual default local command correctly stops before tests until an approved CI seed
exists. This local proof does not substitute for Xcode 26.6 CI acceptance.

One warm package acceptance attempt crashed in the existing Timeline test's array access; it
produced no successful manifest. The preserved failed attempt and subsequent passing execution
remain evidence. No test was removed, retried automatically inside a required collection, or changed
to conceal that failure.

CI elapsed time includes queues and dependency waits; runner time sums occupied job intervals.
Report checkout, simulator startup, build, render, diagnostic teardown and artifact transfer
separately, without summing nested durations. Shard maxima measured on one local Mac are a possible
parallel interval, not observed CI wall time. CI transfer and final performance remain to be measured
after the optimized retry. The first successful native candidate was slower overall; its timings
and the subsequent corrections are retained in the execution record. Global kickstart and related
skills remain unchanged pending confirmation.
