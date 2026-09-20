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

The Python fitting core is implemented as `fit_bayes`, separately from the old
usage model. Ten focused tests cover an independent direct scoring formula,
zero/fractional/default signature priors, held-out output labels, candidate-only
definitions, input identity, admission-before-counting, pruning, determinism,
empty libraries, and input immutability. These and the existing 19 Python tests
pass. The fitter releases each label's raw counts as it emits its sparse record.
Full-library preparation and CPU profiling are now complete; no proof trial has
run for this candidate yet.

The native integration uses a versioned header followed by one label record
per line. Lean streams the file into an inverted index without
retaining both a full per-label feature model and a second inverted copy, or one
large JSON parse tree. Preserve checksum/provenance verification and exact input
index identity. The full-library measurements below include cold loading.

The public `bayes`, `verify`, and three `profile` modes are implemented. Queries
use distinct goal/context constants with unit weights, keep every label's prior,
and default to at most 20,000 evenly sampled postings per symbol. A zero posting
bound scores every stored edge; the default 64-feature artifact remains a
separate approximation. Fusion with sparse and conclusion retrieval is flat RRF
using the existing default parameters. These settings are fixed before any
quality observations for this candidate.

Native fixture checks compare all label scores against an independent direct
formula, including unknown and duplicate query features. They also exercise
training/evaluation overlap, malformed ownership/vocabulary/counts/type hashes,
duplicate records, caller filtering before truncation, state restoration,
unavailable/rolled-back/changed declarations, and a pending theorem whose body
has not been committed. The latter runs under a 30-second process-group timeout.
The full integration suite, all 29 Python checks, and 13 fixture profiling modes
passed. Two initial native-test elaboration errors were corrected before the
successful continuation; already passed preparation checks were retained. The
continuation scope peaked at 252,866,560 bytes with no memory events, under
16 GB and zero swap. These small-fixture timings are not full-library costs or
proof-quality evidence.

For the first full-library candidate, extract theorem-only dependency labels
against the existing public-constant statement index. This keeps the same 254,885
eligible theorem owners and all 188 evaluation-owner exclusions, and lets fusion
share one statement index. The previously prepared public-label artifact took
739 seconds to extract, so it is not silently reused as a free training input.
Measure fresh dependency extraction and fitting, and add the recorded statement
preparation cost when reporting the complete pipeline. Run CPU profiling before
freezing a proof comparison; do not open reserved evaluation locations.

## Full-library preparation and CPU costs

Implementation `8b9ffbe` prepared theorem labels against the public statement
index under one shared 16 GB, zero-swap scope. Fresh dependency extraction took
**762.15 seconds**, with 254,885 eligible owners, 145,736 direct theorem labels,
and 1,536,554 edges. Bayes fitting took **18.40 seconds**, producing **258,016
profiles**, **7,587,133 feature edges**, and a **387,851,440-byte** JSONL artifact.
Adding the earlier measured statement preparation of 232.66 seconds gives
**1,013.21 seconds (16.9 minutes)** for the pipeline. This exceeds the provisional
ten-minute training target; the previous 282-second extraction measurement used
a different prepared statement index and source revision and is not substituted.

Matched CPU profiles use the same 32 public statement types, three repeats,
and 100 suggestions. Every query returned exactly 100 suggestions. These are
latency measurements, not proof coverage.

| Method | Median / p95 query ms | Cold load s | Conclusion initialization s |
|---|---:|---:|---:|
| Bayes | 116.35 / 127.26 | 18.759 | 0 |
| Sparse + Bayes | 276.84 / 350.15 | 18.661 | 0 |
| Sparse + conclusion + Bayes | 319.30 / 467.19 | 18.705 | 28.604 |
| Sparse + conclusion control | 160.29 / 282.52 | 2.917 | 27.824 |

The standalone model meets the provisional 200 ms p95 query target; the fused
variants do not. The shared serial scope peaked at **9,770,303,488 bytes** with
no memory events. No Jev requests or proof trials were made. The full report is
in the benchmark repository's `docs/cpu-selector-profile-bayes-v1.json`.

Next is the predeclared 34-location development screen with all three Bayes
variants, the existing CPU control, and the strongest selected neural control.
The extra fusion cost stays inside the shared proof-search clock. Report quality
and cost together; do not infer a coverage gain from these profiles or redefine
the speed targets. The 122 reserved evaluation locations remain untouched.
