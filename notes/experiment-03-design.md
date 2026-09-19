# Candidate design: structural statement features

Drafted 2026-09-19 while the first proof-neighbor screen is running. No results
from that screen have been used to choose parameters. This is a next hypothesis,
not an implemented or measured improvement.

Symbol sets erase the roles and arrangement of constants. A generic structural
companion can add shallow expression features without a neural encoder or any
proof-body inspection. For each application, retain its head and pairs of that
head with its immediate argument heads, including the argument position. Normalize
bound/local variables to one marker, erase universe levels and binder names,
and keep literal kinds rather than literal values. Traverse binder domain/body,
let values, and projection expressions consistently. Preserve ordinary constant
features so that structural mismatch does not remove all overlap.

Extract from public theorem types in the linked catalog; fit document frequencies
only on the exact eligible owner set. Keep this companion tied to the existing
statement-index identity and type hashes so the dependency model can be reused
without reading proofs again. Query target and local types through the same
feature extractor. Distinguish target and context weights explicitly, rather than
silently changing weights based on outcomes. Avoid features tied to theorem names,
modules, or particular benchmark declarations.

An initial test should compare structural statement retrieval and structural
training-neighbor lookup. For the latter, reuse the frozen dependency-voting rule
and label statistics; only the neighbor metric changes. Candidate premises must
still pass actual-environment and caller filters, whereas training neighbors may
come from the whole eligible library. Preserve the original sparse and dependency
methods for matched ablation. Measure additional preparation, artifact size,
cold load, query latency, and end-to-end replayed proof coverage under 16 GB.

A separate, cheaper hypothesis is bounded applicability reranking of a fixed
retrieved pool: inspect or unify candidate conclusion types with the goal under
saved Lean state, with a deterministic work bound. This must not mutate the
caller's metavariables, smuggle proof terms across snapshots, or hide time outside
the goal clock. Test it separately from new feature extraction to keep causes of
any gain identifiable. No theorem-specific rules or failed-goal repairs.

These are CPU-only candidates. Optional Jev ranking of a short list of analogous
statements could follow, but its calls must be visible to the shared benchmark
budget. A selector making unaccounted private API calls is not an acceptable
comparison; the consumer needs an explicit budgeted callback or equivalent
request accounting before testing that variant.
