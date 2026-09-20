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
