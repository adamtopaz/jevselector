# Generic premise-selector preparation and deployment

Status: agreed requirements and proposed implementation, recorded 2026-09-18.
These are the initial design notes for the public `jevselector` repository.
The benchmark architecture and implementation sequence live in
[jevhammer_benchmark](https://github.com/adamtopaz/jevhammer_benchmark/tree/main/notes).
The initial statement-symbol index, preparation CLI, and standard-selector adapter are now implemented. No pretrained production artifact or performance-parity claim is supplied.

## Objective and boundary

Provide a reusable `Lean.LibrarySuggestions.Selector` backed by artifacts that
are fast to prepare for a whole Lean library and fast to query on CPUs. Use with
JevHammer should achieve at least the strongest historical pipeline's proof
coverage under matched benchmark conditions. Neither a neural model nor a
particular algorithm is required. JevPilot may be used for preparation or query
decisions, with its time and usage accounted for.

"Training" is the generic offline artifact-preparation stage. It can construct
indexes, symbol statistics, dependency structures, weights, learned models,
embeddings, or combinations. Use preparation/training terminology consistently
in the API documentation without assuming gradient-based learning.

Do not bake Mathlib paths, declarations, or benchmark splits into the selector.
Input must be an ordinary Lean project with an explicit module selection and
dependency scope. Preparation on a small independent fixture library should use
the same pipeline as full Mathlib preparation. The benchmark owns its split and
passes exclusions to preparation; the selector does not choose its own test set.

## Preparation inputs and outputs

Proposed inputs:

- Project/toolchain and resolved dependency manifest.
- Root modules or an explicit module manifest.
- Scope policy: target library only or a specified dependency closure.
- Algorithm/feature configuration and any randomness seed.
- Optional exclusion manifest, including declaration identities and grouping.
- Output directory and resource/usage budgets.

An omitted holdout manifest means full-library preparation over the selected
scope. An explicitly empty manifest has the same exclusion semantics but should
remain distinguishable in provenance. Exclusions must resolve against the
supplied snapshot: stale, unknown, or ambiguous identities should be reported,
not silently ignored. Expanding a module exclusion should produce an auditable
list of declarations and associated generated helpers.

Outputs are a versioned artifact bundle plus a preparation report. Record source
and dependency hashes, Lean version, extraction/preparation code revision,
configuration, input scope, exclusion manifest/digest, feature schema, seed,
counts, runtime, memory, artifact sizes, and any external model/call provenance.
An artifact should identify whether it used proofs/dependency labels or only
statement information. Keep enough lineage to determine which source examples
contributed to a fitted component or aggregate.

Do not allow a previously prepared full-data cache to bypass a holdout. Cache
identity must include the effective training inputs, exclusions, and recipe.
Document toolchain/source compatibility and fail clearly for incompatible
artifacts. Portable artifacts must not require the preparer's absolute paths.

## Holdouts and leakage rules

Maintain separate concepts:

1. **Preparation eligibility:** which declarations/proofs may contribute to
   offline artifacts for a particular run.
2. **Retrieval availability:** which declarations exist in the actual Lean
   environment at the current goal and satisfy the caller's filter.

For a benchmark holdout, exclude the owning declaration's proof, proof-derived
dependency labels, recorded proof-state traces, and associated generated
auxiliaries from training. Apply that exclusion before building proof-sensitive
aggregates, edge weights, feature selection, or supervised examples. Filtering
only the final training rows after computing full-data statistics is insufficient.
All locations belonging to the same theorem must share exclusion status.

Statement catalogs need a separately declared policy. Public theorem statements
can be needed to retrieve legitimate earlier premises even when their proofs
are held out. Keeping such a catalog does not authorize using held-out proof
bodies or labels in fitted artifacts. Record whether fitted statement statistics
use held-out declarations, and make that choice explicit in the benchmark
protocol rather than calling it proof supervision. A conservative initial
evaluation can exclude held-out declarations from fitted statistics while still
retaining their statements in an availability-filtered retrieval catalog.

A held-out theorem may be a legitimate premise at a later source location, once
it exists in that location's environment. It must never retrieve itself while
its own proof is being constructed, nor may an index expose later declarations.
Runtime filtering must use the actual environment and selector's `Config.filter`,
not the global artifact catalog as an authority on availability.

The distinction also matters for graph methods: statement/type edges and
proof-body edges have different provenance. A held-out proof must not leak back
through reverse edges, propagated statistics, or lazily loaded proof bodies.
Resolve ownership for compiler-generated declarations; add explicit tests for
these routes before accepting a preparation run for held-out evaluation.

Fully prepared production artifacts, including all Mathlib proofs if the method
uses them, are a supported deployment mode. The benchmark must reject them for
a proof-disjoint evaluation containing those proofs. It must not silently label
a full-data run as held out. Already trained third-party reference models may
have different or unknown training overlap; record this limitation explicitly
and do not claim they satisfy the new preparation contract without evidence.

## Runtime interface

Return ranked `Suggestion`s through Lean's existing selector interface. Honor
the requested maximum and availability filter, preserve meaningful ordering,
and deduplicate names. Use the goal and local context, including relevant local
definitions, while respecting the source environment. Avoid dependence on
JevHammer internals so other clients can use the selector too.

Separate artifact loading/index warmup from goal-dependent selection. Expose
their timing and memory independently. Index imported declarations efficiently
and account for valid current-file declarations that were not present during
offline preparation. Define behavior for missing artifacts, unsupported
declarations, or changed sources; any fallback must be explicit and measurable.
Do not silently load an incompatible/full-data artifact as a benchmark fallback.

CPU execution is the deployment target. Measure cold and warm latency, tail
latency, throughput, resident memory, artifact size, and scaling with library
size. No numerical "fast" threshold has been agreed yet; establish concrete
budgets from baseline measurements before selecting a final implementation.

## Initial research candidates

These are hypotheses to test, not promised performance improvements:

- Sparse statement/symbol indexes with structural features and cheap ranking.
- Proof-dependency frequency or co-occurrence statistics from eligible proofs.
- Bounded dependency-graph expansion with efficiently indexed forward/backward
  neighborhoods and explicit type-edge/proof-edge provenance.
- Small CPU ranking models when their training and inference costs justify them.
- Jev-assisted offline labeling, online reranking, or bounded traversal when
  the end-to-end benefit justifies API latency and shared decision budgets.
- Combinations that improve candidate coverage before a cheap final ranking pass.

Compare preparation/query cost as well as retrieval metrics and complete proof
coverage. Good premise recall alone is not acceptance: JevHammer must be able to
use the returned premises under the same tactic and time budgets. Avoid manual
goal-specific fixes and selecting methods on final held-out outcomes.

Ship documented, reproducible preparation/loading workflows and small offline
fixtures. Larger corpora and prepared artifacts can be separately distributed
with checksums, metadata, and appropriate licensing; they should not turn the
source repository into a local experiment archive.
