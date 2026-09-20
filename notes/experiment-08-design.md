# Bounded rewrite-pattern retrieval

Recorded while experiment 07 is running, before any rewrite-selector proof trial.
This is a general candidate-source hypothesis, not a response to individual
failed benchmark goals. Whole-conclusion matching cannot retrieve every useful
equality or iff whose one side matches a proper subexpression of the goal.

Lean 4.33's `Lean/Meta/Tactic/Rewrites.lean` supplies the relevant design: index
both sides of equalities/iffs, match against subexpressions, and weight forward
matches twice as much as backward matches. Its source explicitly warns that the
recursive subexpression search can revisit repeated expressions. For a bounded
premise selector, deduplicate expressions and bound nodes, depth, and queries.
Return premise names through the usual selector API; do not perform hidden proof
search or require a rewrite-only downstream tactic set.

Extend the explicit signature index with a rewrite-pattern mode, retaining the
existing whole-conclusion mode as the default. Use the same signature-only deny
policy, imported-environment contract, isolated mutable query caches, current-file
rebuilding, availability/type-hash checks, caller filters, and state restoration.
Never read proof bodies or use a process-global tactic cache. Completely generic
wildcard/equality roots remain excluded. Rank each name by its strongest weighted
match, not by the number of duplicate occurrences, with deterministic name ties.

Initial query limits: 256 distinct visited expressions, 64 pattern queries,
depth 8, and at most 8 eligible propositional local hypotheses after the target.
Open binders under their proper Lean contexts and restore all speculative state.
Visit a compound expression before its subexpressions, and a binder body before
its domains. Ignore bare variables, metavariables, sorts, and literals as queries.
Retain the existing 10,000-heartbeat total selector budget. These are fixed generic
resource bounds, not parameters tuned on individual outcomes.

Test proper-subexpression retrieval, both directions, iff names, duplicate
suppression, hypotheses and binders, traversal limits, rollback/unavailable
declarations, mutable-cache isolation, and caller-state isolation. Measure cold
initialization and full-library lookup costs before using the new mode in a proof
comparison. Fixed warmup is `True`, never an evaluation query.

If viable, compare sparse/structural fusion with an additional rewrite source,
and give the neural baseline the same additional source. Use the same Jev
proof-state guidance, tactics, and total search budget. Keep the existing pilot
and larger development results separate from the untouched evaluation split.
No result or superiority is claimed by this design note.

The implementation and native tests now pass, including imported and current-file
rewrites, both directions and directional weighting, iff retrieval, duplicate
names, quantified targets, local hypotheses, node/query/depth bounds, rollback,
independent imported-cache refinement, and caller-filter state. The 19 Python
tests, existing native artifact/holdout/selector tests, and all eight fixture
profiling paths also pass. The final validation scope peaked at 231.61 MB with
no memory events under the 16 GB zero-swap limit. Routine compile/test-harness
errors were corrected before validation completed; no proof benchmark used them.

Review also found that the generic fusion wrapper restored constituent-selector
state but did not restore state after invoking the caller filter itself. That
callback is now isolated, with a regression exercising a mutating filter. Pure
benchmark filters have unchanged behavior. The larger experiment 07 comparison
continues to pin the previously measured implementation; it does not silently
incorporate this extension or fix.

Full-Mathlib profiling completed after the broader structural proof comparison
and its services exited. With implementation `ae41248` (documentation revision
`ed067b0`), 32 identical public statement types × 3 repeats measured rewrite-only
retrieval at **16.20 ms median / 92.18 ms p95** and sparse/rewrite fusion at
**179.97 / 299.02 ms**. The matched public sparse reference was **78.65 / 142.45
ms**. Fixed-`True` initialization took **28.00–28.03 s**; artifact loads were
**2.78–2.92 s** separately. Peak shared scope memory was **3.63 GB**, with no
memory events under 16 GB and zero swap. All methods used fresh Lean processes.

The profiler redirected only the explicit selector imports and plugin from an
audited full-Mathlib setup to the separately validated selector checkout. Its
report records every selector artifact checksum; the benchmark remained pinned
to `b8b0a95`. The profile used no model calls or proof trials. Rewrite-only costs
meet the provisional query target; fusion exceeds the 200 ms p95 target. Proof
coverage remains unmeasured. Complete measurements are in the benchmark repo's
`docs/cpu-selector-profile-rewrites-v1.json`.

The next comparison should preserve the successful conclusion matcher while
adding rewrite-pattern candidates. Use a flat reciprocal-rank fusion of sparse,
conclusion, and rewrite rankings (offset 16, pool factor 2, maximum pool 256).
Give the neural reference the same added source. A cheaper conclusion/rewrite
fusion without the fitted sparse index is also a useful ablation. Before proof
trials, profile both combined paths on the existing fixed query types; two
signature indexes increase initialization and memory, so the previously measured
single-index timings cannot stand in for their combined cost. The profiling CLI
extensions are drafted separately while the reranking benchmark remains pinned.

Profile queries explicitly request 100 suggestions, matching the proof benchmark
and Lean 4.33's existing selector default. Record that limit in new profile
outputs so this assumption is visible even after library defaults change. This
does not change the request size of any previously published measurement.

For the next proof screen, compare current CPU fusion, CPU fusion plus rewrites,
signature-only conclusion/rewrite fusion, current neural fusion, and neural
fusion plus rewrites. Choose each source's premise-reranking flag from the
completed matched-warmup experiment by highest on-time replayed coverage, breaking
ties by total goal time. Keep that flag identical for the source and its rewrite
variant; signature-only uses the CPU flag. Freeze the choices before collection.
Use flat fusion with the same parameters in both three-source variants, and
independent mutable caches for every method. These control choices are development
decisions, not evidence of superiority on reserved evaluation.

A source-level traversal audit found that application arguments were visited but
the function head itself was omitted. An equality between functions can rewrite
that head without matching the entire application. Include the head among the
bounded, deduplicated subexpressions and add a synthetic function-equality
regression. This is a generic traversal correction, unrelated to any benchmark
failure. It is drafted while the reranking run uses the old pinned package;
validate it and remeasure the affected combined paths before deployment. Earlier
rewrite-only measurements continue to describe their explicitly pinned version.

The function-equality regression fails against the previously compiled selector
with `application-head function equality omitted` and passes after rebuilding the
traversal correction. Both native structural/rewrite suites, all 19 Python tests,
and the three conclusion/fusion fixture profiles pass. The profiles use identical
queries and report the explicit 100-suggestion bound. Validation peaked at
304.38 MB with no memory events under 16 GB and zero swap. Full-library profiling
of the corrected traversal and both combined modes is next, before proof trials.

Full-Mathlib profiles of committed `fab11ad` now completed on the same 32 public
statement types × 3 repeats, with 100 suggestions. Rewrite-only lookup measured
**15.99 ms median / 75.10 ms p95** with **28.28 s** initialization. The conclusion/
sparse control measured **156.04 / 284.07 ms**, with **27.40 s** initialization.
Conclusion/rewrite fusion measured **67.14 / 200.25 ms**, with **56.40 s**
initialization; adding sparse retrieval measured **209.73 / 361.55 ms**, with
**55.87 s** initialization. Artifact loading was separately **2.76–2.95 s**.
The shared serial scope peaked at **5.14 GB** with no memory events under 16 GB
and zero swap. No model or proof calls were made. Pure rewrite lookup meets the
provisional 200 ms p95 target; the combined modes exceed it, marginally for
signature-only and materially for the three-source fusion. Retain these costs
when interpreting the upcoming proof screen rather than treating extra sources
as free. The profile report records the exact binary overlay and checksums.
