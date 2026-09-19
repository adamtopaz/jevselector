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
