# Experiment 02: proof-neighbor transfer

Design recorded before candidate outcomes, 2026-09-19.

The first experiment only changes statement-overlap heuristics. This candidate
uses eligible proof bodies as supervised examples, without training a neural
network: retrieve similar theorem statements and recommend the public theorems
used directly by their proofs. Preparation remains a bounded CPU pass.

Prepare the existing statement index with the full cohort exclusion manifest,
then extract dependencies only for the exact eligible owner set in that index.
Do not read excluded owners' proof values, traverse private/helper bodies, or
add proof-derived features to the query index. The extractor must reject missing
proof bodies rather than silently emitting empty training rows. The companion
artifact records its statement-index identity, eligible examples, direct labels,
label type hashes, extraction policy, source fingerprints, checksum, and cost.
Public held-out statements can still be labels in other eligible proofs, but
no held-out proof contributes an example or fitted statistic. Runtime availability
prevents retrieving the target itself or a future/unimported declaration.

First fixed configuration: use the original sparse ranking to choose 32 eligible
training examples; an example at zero-based rank r votes for its dependencies
with weight `1 / (r + 1) / sqrt(max(1, dependencyCount))`. Multiply each label's
total vote by `1 + log((N + 1)/(df + 1))`, where df counts eligible examples using
that label and N is the eligible example count. Training neighbors may come from
the whole prepared training library; returned premises must exist in the actual
goal environment and obey the caller filter. All tie-breaking is deterministic.

Screen direct proof-neighbor retrieval and reciprocal-rank fusion of it with
original sparse retrieval (offset 16, twice the requested pool, cap 256). Keep
the same Jev-guided search, tactic set, and six-second budget. Compare against
fresh sparse and warmed neural references on the existing development cohort;
do not inspect the reserved evaluation split. Record CPU preparation/inference
costs and full verified coverage. No theorem-specific ranking rules are allowed.

This is a hypothesis, not a demonstrated improvement at the time of writing.
Direct references deliberately omit dependencies hidden inside
helpers; a later extension would need an explicit ownership and exclusion audit.

Implementation validation: Python fitting tests and native Lean tests cover
eligibility, missing/duplicate examples, invalid dependency artifacts, future
premise availability, changed statement hashes, zero result limits, and caller
filters. Both legacy imports and modern `module` libraries expose direct proof
references to the extraction command. A private helper fixture confirms that
its body is never opened. The full suite runs in a 16 GB, zero-swap cgroup.
