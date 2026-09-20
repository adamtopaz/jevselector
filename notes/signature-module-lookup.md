# Avoid repeated import-array construction in signature checks

While the native graph cost run on `0ce4ccd` is frozen, the root worktree has a
small optimization draft in `Features.lean`. No proof goal or individual failed
case motivated it. Graph construction calls the generic signature deny predicate
once per available declaration, and traversal calls it again for neighbors.

`EnvironmentHeader.moduleNames` is defined by mapping `.module` over the whole
import array. The old predicate indexed that newly constructed array for every
candidate. Reading `env.header.modules[moduleIdx]` directly obtains the same
module name without rebuilding the array. The generic export `moduleName` helper
has the same repeated mapping and receives the same change. Invalid module indices
are rejected by the deny predicate; valid environments preserve the policy.

Validate canonical old/new graph snapshots using Lake's native plugin setup,
then run the complete selector suite. Preserve the frozen full-Mathlib cost run.
Only after it finishes should the benchmark pin change and a distinctly named
native cost run compare all 384 rankings and costs. This is an implementation
optimization; it does not propose a new scoring rule or establish proof gains.

## Validation

The complete selector suite passes, including 29 Python tests and all native
fixtures, artifact checks and profiles. Old/new graph snapshots generated with
Lake's compiled-plugin setup are byte identical: 54,484 entries, 10,521 forward
keys, SHA-256 `487a7caa8fddce076299ec69e9a18395ce35fad0dee9bf5b129515d5b96c4eed`.
The native constructor timings were 1,254 ms and 958 ms, one run each on the
Lean import set. This is not yet a full-Mathlib speedup claim. Peak validation
memory was 667,406,336 bytes with no memory events under 16 GB and zero swap.
See `docs/signature-module-lookup-validation.json`.

The completed native Mathlib baseline on `0ce4ccd` has 376,987 graph entries.
All 384 cost queries succeeded, but no-expansion traversal alone increased the
base median from 175.64 ms to 676.66 ms, and p95 from 304.21 ms to 2,153.99 ms.
The next isolated native run must preserve all 384 ordered suggestion arrays
while measuring the direct-lookup change. No proof trials have begun.

## Completed native Mathlib comparison

All 384 v4 queries completed with **exactly the same ordered suggestions and
callback/choice payloads** as v3. All repeated rankings remained stable and no
query failed. Full graph initialization improved from **67.840 to 14.719 s**;
structural setup from **30.687 to 6.713 s**. The graph still indexes 376,987
signatures. Costs in median/p95 milliseconds were:

| Mode | Before | After |
|---|---:|---:|
| CPU base | 175.64 / 304.21 | 112.41 / 233.24 |
| No expansion | 676.66 / 2,153.99 | 122.86 / 221.70 |
| Forward | 782.54 / 2,382.00 | 201.81 / 349.83 |
| Backward | 684.82 / 2,228.31 | 123.16 / 220.73 |

These are matched native cost measurements on 32 fixed public statement types,
three repetitions each; no model calls or proof trials. Peak memory was
4,553,039,872 bytes with no memory events under 16 GB and zero swap. Forward
expansion still misses the provisional 200 ms p95 target, so future coverage
results must justify its overhead and actual Jev latency. This optimization
changes implementation cost, not the ranking recipe or established proof score.

Benchmark evidence: `docs/cpu-selector-profile-graph-v4.json` and per-query
digests, plus the preserved v3 comparator. The next small proof screen retains
CPU and both neural-guidance controls under unchanged six-second/three-call
budgets. Reserved evaluation remains untouched.
