# Isolating sparse Bayes approximations

Recorded while the first frozen Bayes proof screen is running. Do not change
that run, its artifacts, or its settings. No failed-goal inspection motivates
this audit: it follows directly from the scoring formula and implementation.

The first model keeps 64 feature deltas per label and samples at most 20,000
postings per query feature. These are two distinct approximations. A skipped
stored posting makes that feature contribute zero to the transformed score;
it therefore treats a known feature as missing for that label. Unlike omitting
a query feature for every label, this can change comparisons between labels.
The missing-feature log weight is -15, so a skipped match need not be a small
perturbation. Feature pruning likewise replaces omitted matches with the
missing-feature score. Both approximations were disclosed, but neither has
been isolated in a proof comparison.

The existing native API already permits exhaustive posting traversal with
`maxPostingsPerSymbol := 0`; the fitter already permits unpruned models with
`--max-features 0`. The profile CLI is being extended to expose
`--bayes-max-postings`, retain the 20,000 default, and record the applied setting
in both raw and summary reports. An optional `--include-suggestions` records
the returned names in rank order after the query timer stops.

After the current proof run and replay finish:

1. Validate the new CLI/native plumbing, including zero and invalid negative
   bounds, without changing the default. Keep the previous cost reports tied
   to their original code and settings.
2. Profile exhaustive versus bounded queries on the same 32 fixed statement
   types, with the same prepared model, suggestion count, process isolation,
   and 16 GB limit. Record aggregate overlap at 8 and 100 suggestions, top-choice
   agreement, and exact-order agreement, without examining individual failed
   proof goals. These are cost and ranking-change measurements, not proof-quality
   results; a changed ranking alone is not evidence of improvement.
3. If exhaustive retrieval is feasible, freeze a small matched comparison to
   test this approximation. Keep the strongest CPU/neural controls and the same
   Jev proof-state budget. Do not infer a gain merely from exact arithmetic.
4. An unpruned fit is a separate candidate. Measure its size, fitting time,
   loading, query costs, and peak memory before any proof run. Reuse the admitted
   dependency artifact with its full lineage; no new extraction is needed for
   a feature-cap change. Report the cost of the complete preparation pipeline.

Query-feature role weights or richer expression features are separate hypotheses;
do not change them in an experiment intended to isolate skipped edges. Preserve
all held-out ownership rules and leave reserved evaluation unopened.

## Tooling validation

The original Bayes screen is complete: no variant beat the existing CPU control.
The profile extensions compile, and all 29 Python checks, native integration
tests, and 16 fixture profiling paths pass. The three Bayes modes each run at
the default cap and at zero; reports retain the exact setting, the optional
rank trace has unique names and excludes the queried statement, and the default
omits the trace. Negative caps fail before creating an output directory. Peak
was 341,233,664 bytes with no memory events under 16 GB and zero swap. These
fixture checks validate the tooling, not the full-library speed or proof value
of exhaustive retrieval.

The next cost screen compares caps 20,000 and zero for each of Bayes,
sparse/Bayes, and sparse/conclusion/Bayes in fresh processes, using exactly the
same 32 public statement types and three repeats as the previous profile. Keep
the original top-64-feature artifact unchanged. Record load and initialization
costs separately, ranking-overlap aggregates, retrieval failures, and resource
events. No Jev calls or proof trials occur in this cost screen.
