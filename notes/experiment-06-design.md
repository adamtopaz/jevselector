# Candidate design: bounded one-premise closure ranking

Implements the separate applicability hypothesis in experiment 03, without
using any individual benchmark failures. Existing JevHammer configurations try
only a small prefix of a 100-premise ranking in their early closing and branching
tactics. A premise farther down the ranking may be applicable to the actual
goal even when symbol overlap alone does not rank it first.

The generic `closingFirst` wrapper asks a base selector for at most 100 premises,
validates availability and caller filters, and deduplicates names. Probe the first
64 remaining candidates under saved Lean state. Apply each to a fresh goal with
the caller's type and local context, then close at most four application subgoals
by local assumption or definitional reflexivity. Limit each probe to 1,000 Lean
heartbeats, including typeclass work. Promote only candidates leaving no expression
metavariables or admissions; preserve the relative order of the others so rewrite
and unfolding premises remain available. Scores encode the resulting rank.

Return only suggestions, never proofs or metavariable IDs created in a probe.
Restore state after the base selector, caller filters, each candidate, and the
whole wrapper, including failures. There are no model calls or proof-body reads.
All query/probe work remains within the benchmark's per-goal clock. The outer
JevHammer tactic and Jev proof-state guidance remain unchanged.

Synthetic tests check promotion, preservation of tail order and flags, filtering
before truncation, unavailable/duplicate names, caller metavariable isolation,
mutating base selectors, zero results, and prefix/subgoal/resource bounds. First
measure CPU query costs using the standard 32-statement × 3-repeat profile. These
are timing measurements on statement types, not proof-success measurements.

If affordable, freeze a screen on the same 34-site development pilot. Compare
the unchanged target selector, its closure wrapper, and the strongest warmed
neural reference. Apply the same wrapper to the neural reference as an additional
control: a generic Lean check helping every retriever must not be advertised as
a uniquely better learned selector. Keep wider-catalog retrieval as a separate
method to avoid attributing a combined effect to either intervention. No reserved
evaluation sites are used for these choices. Parameters are fixed before the
first proof benchmark of this wrapper; publish negative outcomes as well.

The native library build, closure-ranking integration tests, and all 19 Python
tests passed on 2026-09-19 under a 16 GB zero-swap scope. Integration checks also
cover a mutating caller filter, the pool cap, and reflexivity discharge. No
quality claim follows from these synthetic checks. Full-library query profiling
and the fixed development screen remain pending.
