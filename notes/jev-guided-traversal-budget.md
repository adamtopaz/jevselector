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
callback and the base selector, and returns an ordinary Lean selector. Its function type can be
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

## Implementation draft during the posting-cap comparison

The separate JevHammer branch `research/selector-guidance` now has an uncompiled
draft of the callback contract and public tactic integration. The frozen
posting-cap benchmark still uses its original pinned JevHammer; neither that
dependency checkout nor its running search changes.

The proposed callback type is
`String → MVarId → Array Json → MetaM (Array Nat)`: a mathematical question,
current goal, and program-generated choices. The factory receives that callback
and the base standard selector. This keeps the type expressible using Lean alone
and permits `using mySelector guiding myFactory` in the public tactic. Requests
are constructed internally as independent selector questions; arbitrary task
JSON cannot relabel them as proof-state work. A `selectorRankCalls` counter is a
subset of existing premise-call accounting. The same runtime ranking wrapper
validates outputs and enforces the shared call/clock budget.

Draft offline checks cover unchanged base-selector use, zero/single choices,
shared selector/state budgets, malformed/network-failure fallback, required
questions, opaque candidate payloads, the shared clock, public syntax and the
cheap closing prefix's lazy behavior. They have not yet compiled or run. Wait
for the active proof job and its services to finish before native builds, and
check both the public library's Lean version and benchmark compatibility before
pinning a new revision. No graph traversal or quality improvement is claimed.

## Graph implementation draft

`JevSelector/DependencyGraph.lean` now contains an uncompiled prototype. It
caches public imported signature metadata and reverse edges, rebuilds current-file
edges per query, and filters live availability before degrees or traversal bounds.
Imported type hashes are checked when their entries are used. Backward edges may
pass through an available non-premise seed but still inspect only its type.
No proof or definition body is read or retained. There are no fitted proof
statistics, serialized training artifacts, or library-specific rules.

The guided selector calls the supplied base selector once and preserves that
ranking exactly if no graph candidates survive. It seeds from goal/context
constants, prioritizes bounded frontiers by available forward degree, and asks
one batch of three directions per node: none, backward, forward. The default
is one round with eight frontier nodes, 128 visited/reached nodes, 32 edges per
expansion, 1,200 type characters (explicitly marked if truncated), and 10,000
extra query heartbeats. Additional rounds are configurable. Seed overlap and
the existing base order prioritize neighbors deterministically; a second
reciprocal-rank source incorporates reached candidates. These are generic
heuristics, not measured improvements.

The callback is injected, read-only, and returns only checked choice indices.
Invalid replies and ordinary callback failures keep the no-expansion-first
order, leaving the base ranking available. Graph bounds and filtering are
independent of the caller's shared Jev budget. Actual Jev integration must use
the validated JevHammer callback, not a new private client.

`GraphFixture` and `GraphTests.lean` draft synthetic checks for type-versus-body
edges, private/unavailable premises, imported signature mismatch, new/current-file
signatures, edited and rolled-back environments, forward decisions, bounds,
empty requests, invalid/network-failure fallback, callback/filter state isolation,
and a pending theorem whose body is unavailable. Compilation, resource profiling,
end-to-end integration, and proof comparisons are all pending. The frozen Bayes
comparison is unchanged, and reserved evaluation remains unopened.

## Validated implementation after the posting-cap screen

The posting-cap screen is complete and negative; its full results are in
`notes/research-results.md`. The shared-budget API is implemented and published
as JevHammer `2e3df66` on `research/selector-guidance`. Native regression and
consumer builds passed on both Lean 4.34 and benchmark Lean 4.33, with no model
calls. It is ready for a pinned benchmark integration.

The graph implementation now passes the complete selector offline suite,
including all 29 Python tests, existing native/artifact/profile checks, graph
fixtures, and a deliberately unresolved theorem-body test. Both cached and
fresh graph indexes inspect that theorem's available signature without blocking.
See `docs/dependency-graph-validation.json` for the bounded run evidence.

Validation found and fixed two implementation issues before any proof trials.
First, `env.constants` waits for the checked environment even if subsequent
lookups use `findConstVal?`. Imported enumeration now uses module metadata;
current-file enumeration uses `getLocalConstantInfos` while skipping theorem
subdeclarations. Second, full forward neighborhoods exhausted the extra query
budget on a synthetic goal. Guided traversal now considers at most 256 available
forward candidates per node before neighbor ranking and edge selection. The
count is explicitly marked as capped in Jev's choices. Availability filtering
precedes that cap, and the heartbeat limit bounds rejected work as well.
Public forward/backward APIs still expose complete available neighborhoods.

Graph defaults otherwise remain unchanged. The public module export, API guide,
fixtures and offline suite integration are implemented. Full-Mathlib cost
profiling, end-to-end budgeted Jev integration and proof-quality measurements
are still pending. Reserved evaluation remains untouched.
