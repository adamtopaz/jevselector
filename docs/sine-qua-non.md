# Sine Qua Non baseline

`JevSelector.SineQuaNon.selector` wraps the implementation shipped in the pinned
Lean toolchain. It does not reimplement the algorithm or load a neural model.
The implementation is independent of Mathlib and JevHammer.

Lean stores theorem-type symbol frequencies and trigger maps in compiled
modules. Roughly, rare symbols trigger relevant theorems, whose statements
introduce further symbols. Lean traverses these triggers in a priority order
that penalizes expansion depth and less selective triggers. Its code explicitly
describes this ordering as a variation of the original SInE paper; this baseline
is **Lean's Sine Qua Non**, not a claim to reproduce another prover's SInE.

The default settings are `depthFactor = 1.5`, `maxCandidates = 1024`, and
`includeCurrentFile = true`. The depth factor must be finite and at least one.
Candidate retrieval starts at the requested suggestion count (bounded by the
cap), then doubles when filtering/deduplication leaves too few usable premises.
The cap applies to raw imported candidates, including duplicates; it is not a
time bound. Ordinary Lean heartbeat and caller time limits still apply. Zero
maximum suggestions returns immediately. Zero candidate cap disables imported
retrieval while leaving the optional current-file supplement available.

The wrapper applies the standard caller filter before the final maximum.
Current-file candidates use only declarations already present in the actual
environment, sorted by name. Importing this module does not register or replace
the global library suggestion engine. Pass the selector explicitly to a tactic
or register it yourself with `set_library_suggestions`.

No separate fitted artifact or holdout preparation is required. The available
imported statements determine Lean's precomputed statistics. For source-location
benchmarks, the target theorem and later declarations must remain unavailable;
`jevhammer_benchmark` supplies that environment. This differs from the sparse
selector's whole-library catalog with excluded fitting rows, and should be
recorded when comparing the algorithms.

Call `warmup` once before timed queries if reporting warm retrieval. Lean caches
imported maps globally for one fixed import environment. Use separate processes
when comparing different import environments. The benchmark driver does this
per source module and records warmup time separately.

The public benchmark's `Methods.expanded` uses this selector and the expanded
Mathlib tactic set. `Prepared.sparse` uses the same tactics with the prepared
statement-symbol index. Both use Jev for proof-state guidance. Neither uses Jev
premise reranking by default; their `...Reranked` variants enable it explicitly.
