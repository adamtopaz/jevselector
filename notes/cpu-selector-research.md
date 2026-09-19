# CPU selector research

Started 2026-09-19 on `research/cpu-selector`.

## Objective

Develop a generic, publicly usable selector that substantially improves verified
JevHammer proof coverage over the previous neural-premise-selection plus Jev
pipeline. The historical six-second result was 459/1,024, against 350 for full
LeanHammer, but the new package must establish its own matched baseline.
The selector may call Jev. All other preparation and inference runs on CPUs.
Every comparison retains Jev proof-state guidance and the same proof engines.

The user tightened the resource ceiling to **16,000,000,000 bytes total** after
starting this goal. All research services, Lean workers, and preparation jobs
must share one zero-swap cgroup within that limit. Run one heavy job at a time;
use two CPU threads initially. This supersedes the earlier 32 GB ceiling and
the repositories' default 24 GB launcher setting. Do not invoke those defaults
without an explicit 16 GB bound.

Working acceptance target: at least five absolute percentage points over the
strongest matched neural reference, with a declaration-grouped paired 95%
interval excluding zero on an evaluation split not used for method selection.
This is a research target, not a promised result. Repeat final comparisons with
fresh Jev responses. Report losses, incomplete runs, API errors, and late proofs.

CPU cost targets for the initial search: full-Mathlib preparation under ten
minutes and warm query p95 under 200 ms on two CPU threads, with artifact size,
cold loading, and end-to-end goal time measured separately. If a more expensive
candidate is materially stronger, publish the tradeoff instead of redefining
"fast" after observing results. Account for optional Jev calls and latency.

## Evaluation discipline

- Use the existing 34-module development pilot for inexpensive screening, then
  the full 134-location development cohort. Freeze selected methods before
  opening the 122-location reserved evaluation partition. The reserved split is
  too small to guarantee statistical power; expand evaluation with a frozen
  sampling protocol if needed, rather than choosing favorable goals.
- Re-run the external neural selector in the current harness, with and without
  Jev premise reranking, and compare against the stronger reference configuration.
  The old scores are not a measurement of the new packages.
- Keep preparation eligibility separate from query-time availability. Exclude
  all 188 broad-cohort owners before fitting any new statistics or proof labels.
  Support arbitrary libraries, no holdouts, declaration holdouts, and module
  holdouts through the same preparation API.
- Do not inspect individual failed proofs to add theorem-specific rules.
  Analyze aggregate paired coverage, candidate recall, scoring distributions,
  latency, and error rates. Keep all attempts and independently replay every
  success. State explicitly when a result is exploratory.
- Commit every meaningful measured improvement with immutable configuration,
  cohort, preparation lineage, cost, paired gains/losses, and uncertainty.
  Publish negative experiments too; do not promote unmeasured code as better.

## Candidate families

1. Target-aware sparse retrieval: distinguish target symbols from background
   hypotheses, use statement normalization and discriminative rare features,
   and combine complementary rankings without a neural encoder.
2. Structural retrieval: relation heads, typed expression paths, binder-aware
   patterns, and cheap applicability checks on a bounded candidate pool.
3. Proof-neighbor transfer: retrieve related eligible theorem statements and
   transfer their proof dependencies using sparse counts or a small CPU model.
   This requires exclusion before proof extraction/aggregation and tests for
   generated auxiliaries and reverse-edge leakage.
4. Bounded type-dependency traversal: precompute efficient forward/backward
   edges; let Jev choose useful expansions from printed statements. Keep proof
   edges separate from type edges and honor actual Lean availability.
5. Selective Jev use: score a short diverse candidate list, preserve strong
   sparse candidates, or invoke ranking only after cheap retrieval fails to help.
   Account for the shared premise/state-call budget; changes to that allocation
   require a matched comparator and explicit reporting.

## Initial experiment

The benchmark branch of the same name records the frozen first neural/sparse
comparison. Existing preparation and adapters are unchanged for that baseline.
The historical local CPU deployment is used with immutable model/corpus pins
and previously checked agreement with the precomputed embedding vectors.
No claim of proof-disjoint third-party neural training is made.

## Prior work informing later experiments

[Hammer for Coq: Automation for Dependent Type Theory](https://pmc.ncbi.nlm.nih.gov/articles/PMC6044314/)
describes sparse syntactic features, dependency labels, and nearest-neighbor /
naive-Bayes premise selection. This motivates the proof-neighbor candidate above;
it does not establish performance for this Lean implementation. A first Lean
version should extract direct public-theorem references only from eligible proof
bodies, without recursively opening auxiliary definitions, and test exclusions
before any proof-dependent aggregate is constructed.
