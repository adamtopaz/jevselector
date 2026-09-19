# Candidate design: learned sparse premise-usage profiles

Proposed during the first dependency-voting pilot, 2026-09-19. This is a separate
CPU-only hypothesis, not a measured improvement. It uses the
same excluded statement/dependency artifacts and needs no new proof extraction.

Nearest-neighbor transfer considers only a bounded number of similar examples.
A complementary model can aggregate the statement symbols of *all* eligible
proofs using each premise. This is a sparse generative label model, fitted by
counting rather than gradient descent. It may learn useful associations even
when no single neighboring theorem is a close match.

Freeze a first formulation before collecting its outcomes. Treat each distinct
constant in an eligible statement as one token. Let c(p,f) count eligible proofs
using premise p whose statement contains feature f, s(p) count eligible proofs
using p, t(p) = sum_f c(p,f), and b(f) be the global eligible token frequency
normalized to sum to one. With smoothing mass mu = 20, use

    P(f | p) = (c(p,f) + mu*b(f)) / (t(p) + mu)
    prior(p) = (s(p) + 1) / (N + 2)

For a query's unique symbol set Q, rank by the log-likelihood ratio to b:

    log prior(p) - |Q| * log(1 + t(p)/mu)
      + sum_{f in Q} log(1 + c(p,f)/(mu*b(f))).

Target and context have equal weight in this initial formulation. Unknown
features have no fitted evidence and are ignored. A sparse implementation stores
only positive feature corrections. A bounded first artifact can keep each
premise's 64 largest corrections, preserving the full t(p) normalizer and
recording that this is a pruned approximation. Ties use feature/premise names.
Candidate generation uses touched postings, followed by actual-environment,
type-hash, and caller filtering. No global popularity-only suggestions should
appear for a query with no known feature.

Verify the complete eligible example set, label catalog, and statement-artifact
identity before counting. Held-out statements may remain labels in other
eligible proofs, but excluded proofs cannot contribute any counts. Keep fitted
training ownership separate from predicted label names when admitting a cohort.
Record source artifact checksums, formula, pruning, preparation cost, deployment
size, and cold/warm CPU costs. Use the same goal/tactic/Jev budget for a future
paired screen. Do not combine this with structural features or Jev reranking in
its first test; those require their own matched ablations.

This is one fixed, explainable starting point. It is not evidence that a sparse
usage model will beat the neural reference. A failed screen should remain public.

The implementation passed the complete 17-test Python suite and native Lean
integration checks on 2026-09-19, under the 16 GB zero-swap limit. Tests cover
exact smoothing/pruning, excluded and missing examples, permitted held-out labels,
model identity, empty vocabulary, unavailable premises, caller filters, stale
statement hashes, unknown queries, and runtime rejection of excluded examples.
No full-library preparation, query cost, or proof-coverage claim is made yet.

Full-library fitting then completed in 14.08 seconds, reusing the excluded
statement/dependency artifacts: 145,736 premise profiles, 59,171 symbols,
4,971,407 retained feature corrections, and a 251,890,819-byte artifact. Peak
memory was 4,537,978,880 bytes under the 16 GB zero-swap limit, with no limit/OOM
events. These figures exclude the prior extraction costs.

The first full-library query profile failed during loading, before any query or
proof trial. The vocabulary exposed 170 collisions when printed hygienic names
were parsed with `String.toName`; invalid identifier strings became anonymous.
Feature keys now remain opaque text in both sparse and usage retrieval and are
matched against the same `Name.toString` printer used during extraction. This
also fixes previously silent missing/collapsed feature matches in sparse lookup.
Actual public premise names still resolve through the environment as before.
Existing artifact bytes remain valid. The full test suite and explicit hygienic
feature-name regressions pass. Rerun the matched references under the fixed code;
do not combine old and new rankings as though they were identical configurations.
