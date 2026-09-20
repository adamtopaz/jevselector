# Follow-up: term-pattern features for prepared sparse retrieval

MaSh's integration uses bounded term/type patterns with variables replaced by
wildcards. Its feature representation includes more information than constant
sets alone. See [MaSh, section 4.2](https://www.cs.vu.nl/~jbe248/mash.pdf).
Our earlier Bayes experiment tested the scoring recipe with constant features;
it did not test this richer representation.

Revisit the unimplemented shallow-feature proposal in `experiment-03-design.md`.
A Lean-specific experiment could retain existing constant features and add
application-head/argument-head patterns with argument positions. Normalize
variable identities and universes, bound pattern depth, and traverse signatures
only. Keep the feature recipe explicit in artifact metadata and use it equally
for preparation, imported statements, current-file statements, and goal queries.

Fit frequencies only from eligible owners, supporting arbitrary libraries and
optional holdouts. Preserve exact source/type identities and reject mismatched
artifacts. First replace only the sparse component of the current CPU fusion;
keep conclusion matching, tactics and Jev proof-state guidance unchanged. Test
normalization on synthetic fixtures, measure fresh whole-library preparation and
query costs, then freeze a small paired proof screen. Do not combine this with
new graph policies or scheduling changes in its first comparison.

This is a proposed later experiment, not implemented or benchmarked. The live
destination-preview trial remains unchanged and reserved evaluation stays unused.
