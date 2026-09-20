# Candidate design: combine structural matching with statistical retrieval

Source-level hypothesis, recorded before experiment 05/06 proof results. Lean
4.33.0 already exposes `Lean.Meta.LibrarySearch.libSearchFindDecls`, backed by a
lazy discrimination tree over imported declaration signatures. It indexes
conclusions after opening binders and indexes both directions of iff statements.
It discards completely generic wildcard/equality roots. The implementation reads
signatures rather than asynchronous theorem proof values.

This is a potential second source of candidates, independent of bag-of-symbols
similarity. A sparse retriever may never include a directly applicable theorem in
its fixed pool; a bounded closure wrapper cannot recover an absent premise.
Structural matching could improve that pool without neural inference, fitting
proofs, or hand-written domain rules. Consider a standard selector wrapping this
API, plus reciprocal-rank fusion with target-weighted sparse retrieval. Probe
closure only after combining the candidate sources so costs stay bounded.

Before implementation, verify the API's current-environment handling and imported
cache assumptions from `Lean/Meta/LazyDiscrTree.lean`. Reapply `isDeniedPremise`,
the actual-environment check and caller filter before truncation. Deduplicate iff
directions when returning just premise names to JevHammer. Do not claim the
library-search ordering is a calibrated relevance probability. Isolate all Lean
metavariable state; cache only the API's supported persistent data.

Index initialization and first-query lazy expansion must be timed separately from
warm lookup; any warmup must use a fixed synthetic query, never an evaluation goal.
No artifact-training exclusion is needed for read-only signatures of declarations
actually available at a source location, but any fitted sparse companion retains
its usual exclusions. No future/current theorem or unavailable later declaration
may enter the output. Synthetic tests must cover those boundaries before a matched
screen. Compare the strongest neural reference with the same structural/closure
wrapper as appropriate, so generic extra proof search is not mistaken for a
retrieval-specific improvement.

The source audit confirmed that `findMatches` rebuilds a current-file tree per
query, while its supplied `IO.Ref` caches imported signatures without a built-in
environment identity check. Lean's higher-level `libSearchFindDecls` owns a global
ref and also appends dropped current-file entries to a global fallback cache.
For a public reusable selector, prefer an explicit `StructuralIndex` instance
created for one imported environment, using the lower-level tree API without the
dropped-entry fallback cache. Do not store mutable IO refs in an environment
extension (Lean's incremental snapshots may map extension data read-only).

Implementation drafted while the prior benchmark runs against pinned selector
`f601085`; no changes are made to that deployed package or its benchmark sources.
The new instance indexes only not-denied signatures, keeps name/type hashes, and
rebuilds current-file signatures per query. Compare imported-module identities
at query entry, then check candidate availability, type hashes, and caller filters
before deduplication/truncation. Recreate an instance after reloading imports even
if their module names stay the same. Match specificity is the count of non-star
pattern keys; sort descending with deterministic name ties across imported/local
candidates. Open goal binders only under restored Lean state. Do not cache query
goals or current-file entries. Initialization errors must fail explicitly rather
than returning an incomplete tree with discarded diagnostic messages.

Further inspection found that `isDeniedPremise` itself calls `Environment.find?`,
which waits for a complete asynchronous constant (including its proof body).
The structural path therefore mirrors its public name/module/type-prefix deny
extensions using the already supplied signature and `findConstVal?` at query
time. This preserves the policy without forcing proof values just to index types.
Native tests change all three deny extensions after index creation to check that
cached entries cannot bypass updated policy. Other retrieval paths are unchanged.

The initial query limit is 10,000 heartbeats. Initialization uses 6,500 constants
per Lean import task and is measured separately; runtime thread counts and the
aggregate cgroup remain the caller's resource controls. The synthetic warmup is
`True`, so first-use expansion for actual benchmark shapes stays on the goal
clock. No proof values, fitted statistics, or model calls participate.

Native tests cover imported and current-file candidates, quantified goals,
specificity order, both iff directions, deduplication, caller filters/state,
unavailable future declarations, newly available declarations, rollback, changed
imports, zero requests, and explicit resource bounds. These passed after the
previous benchmark and its CPU neural services finished. All 19 Python tests and
the existing native artifact, holdout, and selector integration checks passed.
A profiling-command compile error was fixed; all six profiling paths (sparse,
structural, structural fusion, neighbors, proof fusion, usage) then passed on the
retained fixture artifacts. The profile-validation scope peaked at 208.88 MB with
no memory events under the 16 GB zero-swap limit. Initial test-harness failures
are retained in local logs; no proof benchmark used the unvalidated version.

Full-library cost profiling is next. This validation establishes no proof-coverage
gain. Do not promote the structural candidate until matched proof evidence exists.

Full-Mathlib profiling of `2270359` completed under the 16 GB cap on the same 32
public statement types × 3 repeats for all methods. Public target measured
**78.36 ms median / 144.66 ms p95**; structural retrieval **6.12 / 91.65 ms**;
their rank fusion **159.67 / 289.05 ms**. Structural creation plus fixed `True`
warmup took **27.54–27.56 s**. Artifact loading (needed for profile query sampling,
and for sparse fusion) took **2.77–2.93 s** separately. The shared serial scope
peaked at **4.71 GB**, without memory events. Pure structural lookup meets the
provisional query-cost target; fusion exceeds it and must justify the extra cost
through proof coverage. These are latency measurements, not proof results.

For the live comparison, each structural method must get an independent mutable
cache. Reusing one instance across methods would let later methods benefit from
lazy refinement on the same evaluation goal. `StructuralIndex.freshCache` copies
the fixed warmed tree into a new IO ref, sharing immutable preparation data but
isolating subsequent lazy refinement. Native tests confirm that querying or
clearing a copy leaves the base cache unchanged. Create all per-method copies from
the fixed synthetic base before goal queries; do not copy a goal-warmed instance.
