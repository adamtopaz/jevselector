# Research results

Branch: `research/cpu-selector`. Resource ceiling: **16 GB total**, zero swap.

## 2026-09-19: first current-harness neural reference

The existing prepared sparse selector solved **13/34** pilot development goals;
neural retrieval with Jev premise reranking solved **11/34**. Both used identical
Mathlib tactics and Jev proof-state guidance, six-second goal budgets, and three
shared Jev calls. All **24 successful trials independently replayed**. Sparse
gained three locations and lost one; its paired interval is −5.9 to +17.6 points,
so this is not a significant improvement or a final held-out result.

The second pre-registered neural baseline (without premise reranking) is still
running. Target-weighted retrieval and rank fusion are implemented locally but
not yet validated or benchmarked. The research objective remains unfulfilled.

[Benchmark report and evidence](https://github.com/adamtopaz/jevhammer_benchmark/blob/research/cpu-selector/docs/cpu-selector-research-results.md).
The historical local runtime had to be restored from the Nix binary cache before
service startup. That failed startup produced no benchmark trials or Jev calls.
The successful run's service and Lean processes shared the 16 GB bound; peak
memory was 11.34 GB, with no cgroup limit or OOM events.
