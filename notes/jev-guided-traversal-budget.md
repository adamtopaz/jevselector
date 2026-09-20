# Jev-guided traversal through a shared ranking budget

This is a design recorded while the frozen Bayes screen runs. No implementation
or proof-quality result is claimed. The next decision still uses the complete,
replayed screen; no individual failed goal informed this design.

## Integration findings

The current JevHammer API accepts Lean's standard `Selector` and a separate
`Ranker`. Its private runtime ranking wrapper enforces the shared clock/call
budget, validates permutations, records failures and usage, and falls back to
candidate order. A standard selector is not given this wrapper. Calling a new
Jev client directly from a selector would bypass the experiment's call accounting.

There is a second issue: `Scoring.request` recognizes `premises` and
`premise_refresh`; other task strings receive the proof-continuation question.
A graph action cannot simply be sent under a new task name through this ranker:
it would receive the wrong question. Both budget injection and an explicit
selector-question contract are needed before live model calls.

## Small generic API extension to consider

Provide an optional selector factory that receives a bounded MetaM ranking
callback and returns an ordinary Lean selector. Its function type can be
expressed independently in JevSelector, avoiding a JevHammer dependency there.
JevHammer would create the callback from the same start time, configuration,
ranker and statistics reference used for proof states. Existing `solve` callers
and standard selectors keep their behavior when the factory is absent.

The callback must mark these requests as premise-selection work, irrespective
of the caller-supplied state JSON. Its request schema must explicitly carry the
selector's mathematical question; the question is program-supplied text, and
model output remains only a checked permutation of program-generated choices.
Do not let a selector label its work as a proof-continuation call. Keep response
validation, request timeout, failure fallback, and the shared call limit in the
same path. Factory construction performs no model calls or goal-specific warmup.

The benchmark `Method` would have an optional factory field, passed through to
`solve`; method identity/provenance must record that guidance is enabled. The
same callback can be injected with a deterministic mock for offline tests.
Public tactic syntax also needs a documented way to supply the factory.

## A bounded graph selector

Use constants in the goal and visible local context as seeds. For a constant,
backward edges are constants in its live type; forward edges lead to available
declarations whose types mention it. Read signatures only. Maintain a cached
imported index and a live current-file view, checking availability and statement
hashes before returning or expanding names. Future/unavailable declarations must
not affect query-time frontier degrees or decisions. Retained prepared statement
rows are a lookup catalog, not additional held-out training examples.

For a bounded frontier, generate three choices per node: backward, forward, and
no expansion. Include the node's printed type and direction in each candidate.
Ask whether that direction is the most useful way to find premises for the
current goal. One batch of independent scores yields a permutation; select the
highest-ranked direction separately for each node. This recovers per-node choices
without requiring arbitrary text or a second unaccounted response channel.

Bound frontier size, outgoing edges, rounds, visited nodes, printing, and query
heartbeats before benchmarking. Deduplicate nodes and keep a deterministic
fallback order, with no-expansion first on model failure. Preserve a strong
CPU-retrieval candidate pool; graph traversal supplies additional candidates.
All follow-up rounds and premise refreshes consume the same search budget as
proof-state guidance. Do not treat fewer prompt tokens as extra allowed calls.

## Required checks before trials

Check shared max-call and wall budgets across selector and proof-state requests,
correct request questions, actual premise/state counters, zero/single-choice
handling, invalid response and network-failure fallback, no hidden calls during
warmup, and Lean state restoration. Check graph direction/visibility, imported
cache invalidation, current-file edits/rollback, recursion bounds, duplicate
suppression, and held-out ownership rules. Use synthetic and aggregate checks.

Freeze a small matched comparison with unchanged search budgets, controls and
independent proof replay. Report selector-call costs and any reduction in
proof-state calls. Earlier generic Jev reranking hurt the CPU control under a
shared three-call budget; the new traversal must earn that opportunity cost.
Do not change the active Bayes benchmark or open the reserved evaluation set.
