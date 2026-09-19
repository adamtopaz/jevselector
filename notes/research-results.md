# Research results

Branch: `research/cpu-selector`. Resource ceiling: **16 GB total**, zero swap.

## 2026-09-19: first current-harness neural reference

The existing prepared sparse selector solved **13/34** pilot development goals;
neural retrieval with Jev premise reranking solved **11/34**. Both used identical
Mathlib tactics and Jev proof-state guidance, six-second goal budgets, and three
shared Jev calls. All **24 successful trials independently replayed**. Sparse
gained three locations and lost one; its paired interval is −5.9 to +17.6 points,
so this is not a significant improvement or a final held-out result.

The second pre-registered neural baseline (without premise reranking) solved
**15/34**, versus **14/34** for its fresh sparse control. All 29 successes
independently replayed. Neural gained one and lost none; the paired interval for
neural minus sparse is 0.0 to +8.8 points. It also benefited from the service
embedding cache built by the first run, so the two neural scores are not a clean
reranking ablation. The 15/34 configuration is the stronger observed reference
for subsequent comparisons. Target-weighted retrieval and rank fusion passed
the Python preparation tests and Lean integration checks, including holdout
statistics, filtering, deduplication, and state isolation. They are not yet
benchmarked. Their implementation preserves the default sparse algorithm.
The research objective remains unfulfilled.

[Benchmark report and evidence](https://github.com/adamtopaz/jevhammer_benchmark/blob/research/cpu-selector/docs/cpu-selector-research-results.md).
The historical local runtime had to be restored from the Nix binary cache before
service startup. That failed startup produced no benchmark trials or Jev calls.
The successful run's service and Lean processes shared the 16 GB bound; peak
memory was 11.34 GB, with no cgroup limit or OOM events.

## First candidate CPU profiles

Selector revision `7192e21`, full-Mathlib artifact, 32 deterministic theorem-type
queries repeated three times, two CPU threads, 16 GB zero-swap limit:

| Method | Median | p95 |
|---|---:|---:|
| Sparse | 66.6 ms | 130.1 ms |
| Target-weighted | 66.9 ms | 131.9 ms |
| Rank fusion | 217.3 ms | 342.0 ms |

The target-weighted candidate meets the provisional 200 ms p95 cost target.
Fusion currently misses it; its coverage must justify further optimization.
All methods reuse the existing preparation artifact, with no new training pass.
Cold index loads were 3.8–4.3 seconds; the profile scope peaked at 6.64 GB with
no memory limit/OOM events. These timings are not proof-coverage measurements.

## Experiment 01: first paired proof improvement, objective still open

Selector `7192e21`, identical 34 development locations and search settings:

| Method | On-time verified | Retrieval time |
|---|---:|---:|
| Original sparse | 13/34 | 4.797 s |
| Target-weighted | **14/34** | 4.849 s |
| Rank fusion | 12/34 | 10.286 s |
| Warmed neural reference | **14/34** | 10.675 s |

Target gained one and lost none against sparse; it gained one and lost one
against neural. Its paired interval against neural is −8.8 to +8.8 points, so
this does not establish superiority. It also does not exceed the earlier
15/34 neural observation under different conditions. Retain target weighting
for broader testing; do not promote the slower fusion method.

All 136 expected trials were recorded. Every one of the 54 raw successes
independently replayed; fusion's one late proof does not count toward its 12
on-time successes. The 16 GB zero-swap scope peaked at 9.47 GB without limit/OOM
events. Full costs, errors, configurations, and outcomes are in the linked
benchmark report. No reserved evaluation goals have been run.

The next candidate transfers direct proof dependencies from eligible similar
statements, with exclusions enforced before proof extraction. Its implementation
passed integration validation; no proof-coverage result is claimed yet.

## Experiment 02: dependency preparation and CPU cost

Implementation `ca390e5` passed 11 Python tests plus native Lean exclusion,
availability, state/filter, compatibility, and profiling checks under the 16 GB
cap. The same extraction API works for legacy and modern-module libraries.

Full-Mathlib preparation reused the excluded statement index and took **282.25 s**
to create **254,885 eligible proof examples**, **1,536,554 direct edges**, and
**145,736 labels**. The companion is **65.17 MB**; preparation peaked at **8.01 GB**
with no limit/OOM events. This is a CPU-only fitting pass, with no Jev calls or
neural model. It never traverses excluded proof values or referenced helper bodies.

On the same 32 theorem types × 3 repetitions used for the first CPU profiles:

| Method | Median | p95 |
|---|---:|---:|
| Direct proof-neighbor votes | 45.0 ms | 95.4 ms |
| Sparse + proof-neighbor fusion | 164.5 ms | 278.1 ms |

Direct voting meets the provisional query-cost target; fusion misses it.
Combined index/model loading took 6.35–7.89 s. The profile scope peaked at 2.81 GB
with no memory events. These are cost measurements, not verified proof gains.
The next paired pilot retains target-weighted retrieval and the warmed neural
reference; the reserved evaluation split remains untouched.

## Experiment 02: completed negative proof screen

On the same 34 development locations, direct dependency voting and its sparse
fusion each solved **12/34**, versus **13/34** for target-weighted retrieval and
**14/34** for warmed neural retrieval. All 51 successful proofs independently
replayed; every one was on time. All 136 trials were recorded. Direct voting
gained one and lost three versus neural (paired 95% interval −17.6 to +5.9 points);
fusion gained none and lost two (−14.7 to 0.0 points). Neither configuration should
replace the best current reference.

Retrieval totals were 4.409 s for direct voting, 9.869 s for fusion, 5.668 s for
target weighting, and 10.428 s for neural. All ranking/API failures are retained
(7, 3, 4, and 1 respectively). The shared 16 GB zero-swap scope peaked at 9.19 GB
with no memory events. No reserved evaluation trial has been attempted.

The next candidate fits sparse premise-usage profiles across all eligible proofs,
reusing these artifacts. Its formulation was recorded before testing it in
`notes/experiment-04-design.md`; implementation validation is underway. Structural
retrieval remains an independent planned ablation. The significant-improvement
objective remains unfulfilled.

## Experiment 04: usage-model cost, coverage pending

The sparse usage model fits from the excluded statement and dependency artifacts
in **14.08 s**, producing **145,736 profiles**, **4,971,407 feature corrections**,
and a **251.89 MB** artifact. Fitting peaked at **4.54 GB**, without limit/OOM
events. This is incremental cost; prior statement/dependency extraction is
separate. No Jev call or neural component participates in fitting or querying.

A full-library preflight found that reparsing printed hygienic feature names
collapses some to the anonymous name. Commit `63c3d60` fixes both base sparse and
usage feature keys to remain opaque text. Regression tests and the full suite
pass. The failed preflight ran no queries or proofs; its evidence is retained.
Existing artifact bytes remain unchanged, but matched references must be rerun
under the corrected reader.

On 32 deterministic theorem types × 3 repetitions, corrected usage retrieval
takes **39.1 ms median / 74.1 ms p95**, versus **66.8 / 132.1 ms** for target-weighted
retrieval. Combined usage/index cold loading is **20.71 s**, versus **2.66 s** for
the target index alone. The profile scope peaked at **5.01 GB** with no memory
events. Warm queries meet the provisional cost target, but cold loading remains
an obvious deployment cost. These measurements establish no proof-coverage gain.
