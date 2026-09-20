# Weighted sparse Bayes with an eligible-signature prior

Recorded after the rewrite pilot's 170 proof attempts, while independent replay
is still running. Raw on-time counts are CPU control 16, CPU/rewrite fusion 13,
signature-only 14, neural control 16, and neural/rewrite fusion 14. These are
provisional development outcomes, not a claim about unseen goals. The new
hypothesis follows a source/literature comparison, not inspection of failed goals.

## Motivation and source

[MaSh: Machine Learning for Sledgehammer, section 3.3](https://www.cs.vu.nl/~jbe248/mash.pdf)
describes weighted sparse Bayes with a statement-to-itself prior in addition to
proof-use examples. Its published recipe uses a weight of 20 for that prior, a
factor of 10 for observed features, and −15 for missing features. Our earlier
Dirichlet-smoothed usage model has no corresponding signature prior. That model's
negative benchmark therefore does not test this recipe. A possible benefit is
to preserve a premise's own statement signal while learning relationships between
different statements. This is a hypothesis to measure, not an expected improvement.

## Proposed implementation

Add a separately identified model and CLI preparation path; keep the old usage
algorithm and its results intact. Reuse the validated statement/dependency
artifacts, with no new proof-body traversal. Validate the entire linked example
set before accumulating statistics. Every eligible owner contributes its direct
dependency example and a weighted synthetic self example. Only eligible owners
receive the latter: an excluded owner that occurs as another theorem's dependency
is a possible output label, not an additional training example. Candidate-only
definitions likewise do not become training owners.

For a label, store weighted support and sparse feature frequencies. Use the
published fixed prior/observed/missing weights for the first candidate, rather
than tuning them on individual benchmark outcomes. Keep statement hashes and
exact input-artifact identity. Treat scores as ordering heuristics, not calibrated
probabilities. Return only names available in the current environment, with caller
filtering before truncation and speculative Lean state restored.

Use current eligible statement constants as features initially; richer subterm
features are a distinct future experiment. Support bounded feature storage and
query work, disclose any approximation, and preserve a small exact reference for
checking the sparse scoring transformation. Do not drop label-dependent terms
when rewriting the formula for inverted-posting evaluation. Preserve current-file
and untrained-premise coverage through the existing sparse/structural control
when comparing a fused candidate.

## Validation before proof trials

Test exact toy scores against an independent direct formula; distinguish known
from missing features; ensure signature priors exclude held-out owners, even when
they appear as labels. Reject duplicate/incomplete examples, mismatched artifacts,
invalid parameters, and inconsistent label signatures. Verify deterministic
ordering, availability, filters, and caller state in native Lean.

Prepare from the full eligible Mathlib corpus under the shared 16 GB zero-swap
bound. Report preparation time, artifact size, load cost, memory, and matched CPU
query profiles before a proof trial. Keep training generic over any Lean library
and allow either explicit holdouts or none. The 122 reserved evaluation locations
remain untouched. Freeze a matched development comparison only after these checks;
all arms retain Jev proof-state guidance, the same tactic/time/call budgets, and
independent proof replay. A timing win alone does not establish better proof coverage.
