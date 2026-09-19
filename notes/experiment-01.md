# Experiment 01: target weighting and rank fusion

Hypotheses recorded before collecting candidate outcomes, 2026-09-19.

The baseline treats every target and context constant identically. A large local
context may therefore dilute the conclusion's retrieval signal. The first
candidate gives target symbols weight four and context-only symbols weight one,
using the maximum source weight rather than summing duplicate occurrences.
It divides overlap by `0.25 + 0.75 * size / meanSize`, where meanSize is computed
only from eligible fitting statements. Existing IDF statistics and query-time
availability filtering are unchanged. No held-out statement contributes to the
length statistic. The old square-root ranking remains the default.

The second candidate combines original sparse and target-focused rankings with
reciprocal-rank fusion: sum `1 / (16 + rank)` over the two lists. Each list has
twice the requested length, capped at 256. This retains complementary retrieval
signals without requiring their numeric scores to be calibrated. Ties are
resolved by name, and duplicate names within a list receive one contribution.

Screen both candidates alongside a fresh original sparse control on the fixed
34-site development pilot. Use the same Jev-guided proof-state search, tactics,
six-second goal budget, and three Jev-call budget. Leave premise reranking off
to isolate retrieval. Fit exclusions remain all 188 broad-cohort owners.
Compare with the separately frozen neural baselines; a same-run comparison
against the stronger neural arm is required before claiming superiority.

Before any candidate outcomes, the two completed references gave neural 11/34
with premise reranking and 15/34 without it. The second also used a warmer service
cache. Include the stronger observed neural configuration (no premise reranking)
as a fourth arm in the candidate screen, alongside both candidates and a fresh
sparse control. This changes no candidate parameters and avoids using a weaker
reference. For this fourth arm, explicitly warm both imported and earlier
current-file statement embeddings outside the goal clock, recording that cost
as initialization. This avoids comparing against a neural service disadvantaged
by a cold local-statement cache. Only statements available before the source
declaration are admitted; no target theorem, proof, or model decision is used
by this goal-independent warmup. The source goal is still embedded at query time.
This is a stronger initialization policy than the earlier adapter and must be
reported separately rather than presented as an identical baseline repeat.

This is a deliberately small first experiment. No goal-specific symbols,
theorem names, namespaces, or outcomes enter either algorithm. Report all
candidate results, including regressions, and all latency costs. Do not retune
the constants on this pilot after opening reserved evaluation data.
