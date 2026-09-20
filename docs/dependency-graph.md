# Experimental guided dependency traversal

`JevSelector.DependencyGraph` indexes dependencies between available public
constant signatures. It works with any Lean library and reads no proof or
definition bodies. Its backward edges are constants mentioned in a type; its
forward edges are declarations whose types mention a constant. These are
signature dependencies, not the full graph of proof-body dependencies.

Create the graph once per import environment in `MetaM`:

```lean
let graph ← JevSelector.DependencyGraph.create
let previous ← graph.backward ``Nat.add_comm
let following ← graph.forward ``Nat.add
```

The graph stores imported types' hashes and constant names. Queries rebuild
current-file signature information, check live availability and imported hashes,
and honor edited or rolled-back environments. Changing imports requires a fresh
index. Enumeration uses imported module metadata and Lean's asynchronous local
signature API, so it does not wait for an unfinished theorem body.

`graph.guided options rank base` is a standard `LibrarySuggestions.Selector`.
It first runs `base`, then starts from constants in the goal and visible local
context. At each bounded round it supplies three choices per frontier constant:
no expansion, backward, and forward. Each choice includes the pretty-printed
type, direction, and bounded neighborhood counts. The supplied ranking chooses
one direction per constant. Seed overlap and the base ranking prioritize
neighbors; reciprocal-rank fusion incorporates reached candidates into the base
ranking. Invalid replies and callback failures choose no expansion, preserving
the base ranking. Lean state changes from callbacks and filters are restored.

The defaults are one round, eight frontier constants, 128 visited/reached names,
256 available forward candidates per node, 32 edges followed per expansion,
1,200 printed type characters, and 10,000 extra query heartbeats. Printing and
neighborhood caps are explicit in the JSON choices. Unavailable candidates are
filtered before consuming the forward candidate cap. Public `forward` and
`backward` queries return the full available neighborhood; the guided traversal
has the extra bounds. Base retrieval retains its own work budget.

An opt-in destination preview supplies more evidence to the ranker:

```lean
let options : JevSelector.GraphConfig := {
  maxPreviewCandidates := 3
  maxPreviewTypeChars := 480 }
let selector := graph.guided options rank base
```

Preview candidates follow the same neighbor ordering and edge bound as expansion.
Only available, admissible destinations passing the caller's filter are shown;
filtering precedes the display limit. Each entry includes its name, printed type,
and truncation flag. `preview_omitted` reports further display-eligible entries
among the considered edges, while `preview_considered_edges` counts those edges
before final-premise filtering. The full neighborhood counts can include
intermediate constants that are not admissible final premises. Preview printing
uses the same query budget and introduces no extra ranking call. The default
`maxPreviewCandidates := 0` retains the original request format.

The injected `GraphRanker` type is:

```lean
String → Lean.MVarId → Array Lean.Json → Lean.MetaM (Array Nat)
```

It takes the mathematical question, goal, and choices, and returns a permutation
of their indices. This module creates no client and imports neither JevHammer nor
Mathlib. With JevHammer's selector-guidance API, `graph.guided options` has the
structural type of a `SelectorFactory`: supply it through `solve`'s optional
`selectorFactory` argument, or a closed factory through the tactic's `guiding`
clause. This shares the search's Jev client, call allowance, clock, and ledger.
Do not create a separate client to bypass those benchmark budgets.

No training holdouts are needed for the signature graph itself, because it fits
no proof-derived statistics. A prepared base selector must still enforce its
own holdouts. Current-file declarations must be available at the actual query
position; a later theorem is never a permissible premise merely because it
appears in a prepared catalog.

The graph is experimental. Synthetic tests check directions, bounds, visibility,
environment changes, callback failures, state isolation, and explicitly unresolved
proofs. Full-library costs and proof-quality improvements require separate
measurement; graph traversal is not yet a recommended replacement for the
best measured CPU selector.
