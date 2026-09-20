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
