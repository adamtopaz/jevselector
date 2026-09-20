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

This is only a research plan. It is not implemented or benchmarked, and does not
justify a claim of improvement over neural selection.
