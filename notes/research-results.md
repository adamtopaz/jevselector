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

## Experiment 04: completed negative proof screen

Under the corrected reader `63c3d60`, usage profiles solved **10/34**, versus
**14/34** for both target-weighted and warmed neural retrieval. Usage gained no
locations and lost four against each reference; its paired interval versus neural
is −23.5 to −2.9 percentage points. All 102 trials were recorded, all 38 successes
independently replayed, and no success was late. Do not promote this configuration.

Retrieval totals were 2.431 s for usage, 5.104 s for target, and 10.807 s for neural;
the faster lookup did not compensate for poorer premise order. All ranking/API
errors remain in results (4, 5, and 2 respectively). Combined peak memory was
11.42 GB under the 16 GB zero-swap cap, with no memory events. The reserved
evaluation split remains untouched. Full evidence is in the benchmark report.

An opt-in public-constant catalog and direct-label policy are now being validated.
They admit definitions/constructors as candidates without expanding proof-training
owners or opening definition bodies. This follows a source-level audit of the
neural adapter's broader candidate universe, not inspection of failed goals.
The significant-improvement objective remains open.

## Experiments 05/06: preparation and CPU cost, proof screen pending

Public-catalog preparation adds **63,162 candidate-only constants** to the same
**254,885 eligible theorem owners**, taking **232.66 s** for a **183.78 MB**
statement artifact. Its direct public-label companion has **187,655 labels** and
**5,249,157 edges**, taking **739.28 s** and **129.56 MB**. Audits confirm identical
original theorem rows, fitted symbol weights, owners/exclusions, original theorem
edges, and original label hashes/weights. Definition bodies remain unopened.

Bounded closure ranking is implemented in `f601085`, with native integration and
19 Python tests passing. It is a generic CPU wrapper for any standard selector,
including neural selection; it returns names after restoring all speculative
Lean state. Parameters are fixed before the first proof screen.

On the matched 32 theorem-type queries × 3 repetitions, target retrieval takes
**65.62 ms median / 128.19 ms p95**, while adding closure ranking takes
**105.90 / 216.91 ms**. The slightly higher-than-target p95 is an explicit cost,
not a reason to silently reduce work before the first screen. Public-target and
public-neighbor methods take **83.40 / 152.40 ms** and **52.73 / 86.35 ms** on 32
types sampled from their expanded catalog; these are different query types from
the original-catalog profile and must not be called a matched latency comparison.
Their cold loads are **2.84 s** and **7.39 s**. The serial profile scope peaked at
**3.85 GB**, with no memory events under the 16 GB zero-swap cap.

The next pilot has six arms: unchanged target, public target, public neighbors,
closure-ranked target, warmed neural, and identically closure-ranked neural. All
use Jev proof-state guidance with unchanged tactic/search settings. It reuses
the same 34 development sites and leaves reserved evaluation untouched. No
coverage gain has yet been measured for these candidates.

## Experiments 05/06: completed screen, one-goal public-catalog lead

The public catalog solved **15/34**, versus **14/34** for original target retrieval,
**12/34** for public-label neighbors, **13/34** for closure-ranked target, and
**14/34** for both warmed neural and closure-ranked neural. All **204 trials**
completed and **all 82 successful proofs independently replayed**; none were late.

Public target gained one location and lost none against original target. Against
either neural arm it gained two and lost one, with paired declaration-bootstrap
95% interval **−5.9 to +11.8 percentage points**. This is an exploratory one-goal
lead; significant superiority remains unproved. Retain the wider catalog as a
promising cheap candidate, but do not promote either public-label voting or
closure ranking as a stronger configuration on this evidence.

Goal/retrieval totals in seconds were **118.923/5.629** for target,
**113.456/5.399** for public target, **124.376/5.003** for public neighbors,
**122.517/7.838** for closure target, **120.244/10.614** for neural, and
**122.997/14.109** for closure neural. All **23 ranking/API errors** are retained
(3, 5, 5, 4, 1, 5 by arm). The run made **326 requests**, with **1,836,304 reported
input tokens**, **43,911 output tokens**, and unknown usage for **15** requests.
Combined peak memory was **12.85 GB**, with no memory events under the **16 GB
zero-swap cap**. Services stopped after replay. Reserved evaluation remains unused.

Complete evidence is published as `cpu-selector-public-closure-v1.json` and its
per-location trial file in the benchmark repository. The structural signature
candidate is being validated next. The significant-improvement goal is still open.

## Experiment 07: structural retrieval CPU profile

The signature-only structural index is implemented and passes native boundary
checks, the 19 Python tests, and fixture profiles. Full-Mathlib initialization plus
fixed `True` warmup takes **27.54–27.56 s**. Across the same 32 public statement
types × 3 repeats, structural lookup takes **6.12 ms median / 91.65 ms p95**, versus
**78.36 / 144.66 ms** for public-target retrieval. Their rank fusion takes
**159.67 / 289.05 ms**. The 16 GB zero-swap scope peaked at **4.71 GB**, with no
memory events. Artifact loading is reported separately; pure structural selection
requires no fitted model, and the profile uses that artifact only to choose queries.

Fusion misses the provisional 200 ms p95 target; retain this cost explicitly in
the first proof screen. These timings alone establish no proof-quality gain.
Competing methods use independent mutable structural caches copied from a fixed warmed base,
so no method benefits from another method's evaluation-goal refinement. The copy
isolation regression passes. Reserved evaluation remains unused.

## Experiment 07: verified structural fusion pilot

The five-arm screen completed all **170 trials**, and all **70 successful proofs
independently replayed**. Public sparse + structural fusion solved **16/34**,
public sparse **15/34**, structural-only **12/34**, warmed neural **14/34**, and
neural + structural **13/34**. None were late or budget-blocked; no modules failed.
The deployed selector was `b8b0a95`, benchmark `debb49f`, with fixed parameters.

CPU fusion gained one and lost none against sparse, two and lost none against
neural, and three and lost none against neural fusion. Against neural its paired
declaration-bootstrap 95% interval is **0 to +14.7 percentage points**; against
neural fusion, **0 to +17.6 points**. The observed +5.9-point gain over neural is
promising but does not meet the significance requirement, and this pilot was
already exposed during development. Advance the unchanged public sparse and
fusion candidates to the full 134-location development comparison against both
neural arms. Do not claim the research goal is complete.

Goal/retrieval totals in seconds were **112.113/5.354** for public sparse,
**126.089/0.666** for structural, **116.620/6.820** for CPU fusion,
**120.828/10.321** for neural, and **126.641/12.245** for neural fusion.
The separate full-library fusion query p95 remains above the provisional target.
All **15 ranking/API failures** remain counted (6, 3, 3, 1, 2 by arm).
There were **244 Jev requests**, **1,413,999 reported input tokens**, **34,304
output tokens**, and **8** unknown-usage requests. Combined peak was **11.82 GB**,
without memory events under the **16 GB zero-swap cap**; services stopped after
replay. All 122 reserved evaluation locations remain untouched.

Complete reproducible evidence is in the benchmark repository's
`docs/cpu-selector-structural-v1.json` and companion trial file. A complementary
bounded rewrite-pattern source is drafted separately in experiment 08; it was
not part of this measured improvement.

## Experiment 07: full development, CPU gain over sparse but no neural advantage

All **536 trials** at **134 development locations / 99 owners** completed, and
all **247 successful proofs independently replayed**. Public sparse solved
**57/134**, sparse + structural fusion **63/134**, plain warmed neural **63/134**,
and neural + structural fusion **64/134**. None were late or budget-blocked.
Selector `b8b0a95` and benchmark `405f7fe` retained the frozen six-second budgets,
tactics, and Jev state guidance without premise reranking.

CPU fusion gained seven and lost one against sparse, an observed **+4.5 points**
with declaration-grouped paired 95% interval **+0.75 to +8.73 points**. Against
plain neural it gained seven and lost seven (**−5.15 to +5.60 points**); against
neural fusion it gained five and lost six (**−5.51 to +4.32 points**). This is a
meaningful measured CPU improvement over sparse, but no advantage over the best
neural approach. The significant-improvement research goal remains unfulfilled.

On the original 34 pilot locations, counts again were sparse 15, CPU fusion 16,
neural 14, neural fusion 13. On 19 other locations of pilot owners they were
9/10/9/9. On **81 locations from 65 owners absent from the selector pilot**, they
were **33/37/40/42**. These are exploratory development strata, with prior
broad-baseline exposure, not independent test results. The apparent pilot lead
did not generalize into a lead on the larger development cohort.

Goal/retrieval times in seconds were **424.942/22.724** (sparse),
**414.761/26.698** (CPU fusion), **403.897/54.893** (neural), and
**417.450/62.836** (neural fusion). CPU retrieval remains cheaper, while the
full-library fusion p95 cost caveat remains unchanged. There were **32 ranking
failures** (9/13/5/5), **675 requests**, **3,611,284 reported input tokens**,
**96,696 output tokens**, and **14** unknown-usage requests. Peak was **10.51 GB**,
with no memory events under the **16 GB zero-swap cap**. No reserved evaluation
location has been tried.

A host environment change interrupted the launcher after 92 complete trial
groups; only its original neural services survived. Recovery resumed the 42
untouched goals in the same cgroup using those same live services and caches,
preserving all 368 previous trials and 410 request records. Nothing was retried
or reset. Full source-bound replay subsequently passed and services stopped.
The benchmark report retains the interruption audit and all outcomes as
`docs/cpu-selector-structural-broad-v1.json` and its companion trial file.

The frozen rule selects CPU fusion and neural fusion for experiment 09's matched
warmup reranking check. That test must precede any final superiority claim.
Experiment 08's bounded rewrite mode remains separate; it has passed native
tests and fixture profiles, but its full-library costs and proof value are pending.

## Experiment 09: matched-warmup premise reranking

The four-arm comparison completed **136 trials** at the same 34 development
locations. All **57 successful proofs independently replayed**; one neural-reranked
proof was late and is excluded from coverage. CPU fusion in native order solved
**16/34**, CPU fusion with Jev premise reranking **13/34**, neural fusion in native
order **13/34**, and reranked neural fusion **14/34** on time. Selector `b8b0a95`
and benchmark `2a5fffb` retained the same six-second, three-call budgets and Jev
state guidance. Imported and earlier current-file neural statement embeddings were
warmed outside goal timing; goal embeddings remained timed.

CPU native order gained three and lost none against CPU reranking. Against the
stronger reranked neural arm it gained three and lost one, an observed **+5.9
points** with paired 95% interval **−2.94 to +17.65 points**. This exposed pilot
does not establish superiority. The earlier 134-location result still supplies
the broader evidence, where CPU fusion did not beat neural fusion. No reserved
evaluation location has been tried.

Goal/retrieval totals in seconds were **116.441/6.728**, **137.314/6.532**,
**125.498/11.889**, and **139.348/11.773**, respectively. Native CPU/neural arms
made **42/46 state-ranking calls** and no premise calls; reranked arms made
**49/50 premise calls** and **24/23 state calls**. Reported input tokens were
**240,565 / 1,064,223 / 291,528 / 1,118,159**. Reranking spent roughly four times
the input tokens and left fewer calls for state guidance; this experiment does
not distinguish ranking quality from that budget tradeoff.

All **7 ranking/API errors** are retained (2/3/2/0). There were **234 requests**,
**2,714,475 reported input tokens**, **184,811 output tokens**, and one request of
unknown usage. Peak was **11.01 GB**, with no memory events under **16 GB and zero
swap**. There were no budget-blocked trials. Services stopped after replay.

The frozen rule for the next rewrite-source screen selects **native CPU order**
and **Jev-reranked neural order** by on-time verified coverage. Each source and its
rewrite variant will share that setting; the signature-only ablation uses the CPU
setting. This is a development choice, not a claim that either flag is optimal
on unseen goals. Full configurations, calls, costs, intervals, and all outcomes
are published in the benchmark repository's `docs/cpu-selector-rerank-v1.json`
and companion trial file. The research goal remains open.
