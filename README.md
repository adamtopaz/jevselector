# jevselector

Portable premise-selector preparation and CPU retrieval for Lean. Implements
Lean's standard `Lean.LibrarySuggestions.Selector`; no Mathlib, JevHammer,
Python runtime, neural model, or network service is required for **querying**.
The preparation CLI uses Python's standard library and Lake. Selector modules
are precompiled into native libraries using Lean's C toolchain.

The initial algorithm indexes constants in theorem **types** and ranks weighted
symbol overlap with the goal and local context. The statement index never reads proof bodies.
This is an inspectable baseline for further experiments, **not yet a demonstrated
replacement for the strongest neural-selector/JevHammer pipeline**.
The library also supplies a configurable Sine Qua Non baseline using Lean's
built-in retrieval algorithm, without any external preparation or service.

The `research/cpu-selector` branch also contains experimental target-weighted
retrieval and reciprocal-rank fusion. These are candidates under evaluation,
not demonstrated improvements. See the [research protocol](notes/cpu-selector-research.md)
and [first experiment](notes/experiment-01.md).
To run the experimental commands below, pin both the Lake dependency and Python
package to the same research commit (`git+https://github.com/adamtopaz/jevselector@COMMIT`
for pip). The `main` installation example is for the released baseline.

## Install

Requires Lean **4.33.0**, Lake, and Python **3.10+** for preparation. Add to a
project's `lakefile.toml` (pin a release or commit for reproducibility):

```toml
[[require]]
name = "jevselector"
git = "https://github.com/adamtopaz/jevselector"
rev = "main"
```

```sh
lake update
lake build JevSelector
python -m pip install 'git+https://github.com/adamtopaz/jevselector'
```

## Sine Qua Non baseline

```lean
import JevSelector.SineQuaNon

def mySineSelector : Lean.LibrarySuggestions.Selector :=
  JevSelector.SineQuaNon.selector {
    depthFactor := 1.5
    maxCandidates := 1024
    includeCurrentFile := true }
```

Use `mySineSelector` with `jev_hammer ... using mySineSelector`, or pass it to
any consumer of Lean's selector interface. `SineQuaNon.warmup` loads the imported
trigger and symbol-frequency maps separately from goal-dependent retrieval.
This uses only Lean's compiled statement statistics; no index file, Python,
training run, or neural component is needed.

Imported premises retain Lean's Sine Qua Non priority ordering. The wrapper
filters unavailable/denied premises, respects the caller filter, and removes
duplicates. When filtering leaves too few results, it doubles the raw retrieval
request up to `maxCandidates`. Optional earlier current-file theorems (including
private ones) are sorted by name and interleaved 1:1 with imported suggestions.
No scores from different selectors are compared. See
[baseline details](docs/sine-qua-non.md) for bounds and benchmark settings.

## Experimental proof-neighbor selection

The research branch has an optional CPU model that transfers dependencies from
similar eligible theorem statements. It is under evaluation; it is not yet a
demonstrated improvement over the neural reference. Prepare the statement index
with the desired exclusions first, then create its dependency companion:

```sh
jevselector dependencies --modules MyLibrary --index artifacts/heldout/index.json \
  --output artifacts/proof-neighbors --memory-limit 16000000000
jevselector verify artifacts/proof-neighbors
```

Extraction reads only eligible owners' proof values. It records direct references
to public theorems and does not recursively open private/helper proofs. Missing
or incomplete eligible proof bodies are errors. Exclude unfinished declarations
before preparation. A production index without exclusions uses the same command.

In Lean, load the statement index once, then call
`JevSelector.loadDependencies idx "artifacts/proof-neighbors/dependencies.json"`.
The resulting model exposes `model.selector {}` and `model.hybridSelector {}` as
standard Lean selectors; the hybrid combines dependency votes with sparse
retrieval. Call `model.validateEnvironment` for warmup and
`model.validateHoldouts owners` before evaluation. Querying needs no Python,
proof-body access, neural model, or network call. JevHammer can use either
selector through its ordinary `using` or `solve` interface.

Training examples may come from the whole prepared library, including modules
not imported at a query. Returned premises must be present in the actual Lean
environment and obey the caller filter. Only eligible proofs contribute examples
or label-frequency statistics. See the [experiment protocol](notes/experiment-02.md)
for the fixed initial ranking and its limitations.

## Experimental sparse premise-usage model

The research branch also has a candidate that fits symbol profiles from **all**
eligible proof examples using each premise. This is a smoothed sparse language
model, built by CPU counting with no neural encoder or Jev call. It reuses the
existing excluded artifacts; no proof extraction is repeated:

```sh
jevselector usage --index artifacts/heldout/index.json \
  --dependencies artifacts/proof-neighbors/dependencies.json \
  --output artifacts/usage --memory-limit 16000000000
jevselector verify artifacts/usage
```

Load with `JevSelector.loadUsage idx "artifacts/usage/usage.json"`, then use
`model.selector {}`, `model.validateEnvironment`, and `model.validateHoldouts`.
The query uses only the statement index and usage artifact, with no Python,
service, or proof-body access. The model ranks learned usage profiles rather
than the premises' own statement overlap. See the
[fixed formulation](notes/experiment-04-design.md) for smoothing, pruning, and
limits. The implementation passes preparation and native integration tests;
no coverage gain is claimed.

## Experimental weighted sparse Bayes

This CPU-only candidate learns premise profiles from eligible proof dependencies
and a weighted example matching each eligible theorem to its own statement.
The statement prior preserves a premise's own features even when few proofs use
it. Held-out declarations and candidate-only definitions never supply training
examples or statement priors, although dependencies can still name them as labels.
There is no measured proof-coverage result for this candidate yet.

```sh
jevselector bayes --index artifacts/heldout/index.json \
  --dependencies artifacts/proof-neighbors/dependencies.json \
  --output artifacts/bayes --memory-limit 16000000000
jevselector verify artifacts/bayes
```

Load with `JevSelector.loadBayes idx "artifacts/bayes/bayes.jsonl"`. The returned
model supplies `model.selector {}`, `model.validateEnvironment`, and
`model.validateHoldouts owners`. It uses the standard selector interface; no
Python, proof-body access, or network service is needed at query time. Fuse it
with `idx.targetSelector` or structural retrieval to cover edited and untrained
premises. Available imported signatures must match the artifact; changed
current-file labels are skipped. Filters run before truncation with Lean state
restored between calls.

The default recipe uses statement-prior weight 20, observed-feature factor 10,
and missing-feature log weight −15. Each premise keeps its 64 largest feature
contributions; `--max-features 0` keeps all. Query features are the distinct
constants in the goal and visible context, with unit weights. A query considers
all label priors, even without a feature match, and samples at most 20,000
postings per feature by default. `maxPostingsPerSymbol := 0` scores the stored
model exhaustively; the artifact's feature pruning is a separate approximation.
Returned suggestion scores encode rank, not calibrated probability.

The versioned JSONL artifact has one header and one record per premise. Loading
streams records into an inverted index. The header records ownership, input
identity, parameters, feature vocabulary, and provenance; checksum verification
uses bounded reads. Profile with `--bayes artifacts/bayes/bayes.jsonl` and
`--method bayes`, `bayes-target`, or `bayes-structural-target`. The last two use
flat reciprocal-rank fusion. See the [fixed recipe](notes/experiment-10-design.md).
Pass `--bayes-max-postings 0` to profile exhaustive traversal of the stored model;
the default is 20,000 postings per feature. The applied cap is recorded as
`bayesMaxPostingsPerSymbol` in both profiling reports. Artifact feature pruning
is independent of this query option.
Add `--include-suggestions` to include returned premise names in rank order in
`queries.json`, for aggregate ranking comparisons. Names are recorded after the
query timer stops; the default reports only counts and timings.
Full-Mathlib profiling of `8b9ffbe` measured standalone Bayes at 116.4 ms median /
127.3 ms p95, with 18.8 s cold loading. Adding sparse retrieval measured
276.8 / 350.2 ms; adding conclusion retrieval as well measured 319.3 / 467.2 ms,
plus 28.6 s conclusion initialization. The CPU fit took 18.4 s; including statement
and dependency preparation gives 16.9 minutes. Peak across serial preparation
and profiles was 9.77 GB. These are cost measurements on 32 fixed statement types
with three repeats, not evidence of better proof coverage.


## Prepare any library

Run from a Lake project importing the desired library:

```sh
jevselector prepare --modules MyLibrary --scope MyLibrary --output artifacts/full
jevselector verify artifacts/full
```

An experimental opt-in catalog also admits public definitions and constructors:

```sh
jevselector prepare --modules MyLibrary --catalog public-constants \
  --exclude holdouts.json --output artifacts/public-catalog
jevselector dependencies --modules MyLibrary --index artifacts/public-catalog/index.json \
  --labels public-constants --output artifacts/public-dependencies
```

The two options are independent. The expanded statement catalog records
non-theorems as `candidateOnly`: they can be retrieved, but do not contribute to
fitted statistics or become proof examples. Public labels can include definitions
directly referenced by eligible theorem proofs. Their bodies are never opened.
The dependency extractor checks that each eligible owner is an original theorem
before obtaining its proof value. Default catalogs and labels remain theorem-only.
The implementation passes preparation and native integration checks; it has no
measured coverage gain.

`--modules` selects imports to load. Repeat `--scope` to select module-name
prefixes inside that loaded environment. Without `--scope`, the root modules
are the prefixes. For Mathlib, use `--modules Mathlib --scope Mathlib` in a
project depending on Mathlib and this package. No Mathlib-specific extraction
code or pre-existing dataset is used.

For a held-out evaluation:

```json
{"schema":1,"declarations":["MyLibrary.myTheorem"],"modules":[]}
```

```sh
jevselector prepare --modules MyLibrary --exclude holdouts.json --output artifacts/heldout
```

Exclusions resolve against the exported scope; unknown names fail. Module
exclusions use exact module names. Declaration exclusions also cover named
children. Private/generated declarations denied by Lean's suggestion filter
never enter the theorem catalog. An omitted holdout prepares the full selected
library; an explicitly empty holdout has the same fitting semantics and different
provenance. Both production and evaluation artifacts use the same pipeline.

## Use in Lean

```lean
import JevSelector

open Lean Meta

-- Load once in application initialization; retain the Index between queries.
def loadMyIndex : IO JevSelector.Index :=
  JevSelector.load "artifacts/heldout/index.json"

-- idx.selector is a standard LibrarySuggestions.Selector.
def suggestions (idx : JevSelector.Index) (goal : MVarId) :
    MetaM (Array LibrarySuggestions.Suggestion) :=
  idx.selector {} goal { maxSuggestions := 100 }
```

With JevHammer, pass `idx.selector` to `JevHammer.solve`, or define a cached
named selector for the `jev_hammer ... using mySelector` tactic. See the
[benchmark integration](https://github.com/adamtopaz/jevhammer_benchmark/tree/main/integrations/selector)
for a complete adapter with warmup and holdout admission.

On the research branch, `idx.targetSelector` emphasizes symbols in the target;
`idx.ensembleSelector {}` combines that ranking with the original sparse ranking.
Both reuse the same index and standard selector interface. `JevSelector.fuse`
also accepts other selector arrays. Constituent numeric scores need not be
comparable, and each constituent runs with isolated Lean state. External IO
cannot be rolled back. Importing the module does not register a global selector.

`JevSelector.closingFirst idx.targetSelector {}` is an experimental, CPU-only
wrapper for any standard selector. It retrieves at most 100 names, probes the
first 64 after filtering, and promotes those that close the goal by application
followed by local assumptions or reflexivity (at most four subgoals). Each probe
has a 1,000-heartbeat limit and restores Lean state; the wrapper returns names,
not speculative proof terms. Other names retain their relative order. Configure
these bounds with `ClosingConfig`. This is not a demonstrated coverage gain;
use `profile --method closing-target` to measure its additional cost.

`JevSelector.StructuralIndex.create` is a separate experimental candidate source
using Lean's lazy discrimination tree over available declaration signatures. It
needs no proof corpus or fitted artifact. Construct it in `MetaM` once per imported
environment, then pass `model.selector {}` to the standard selector interface.
Current-file signatures are rebuilt at query time; imported signatures are cached
in the instance. Recreate the instance after changing or reloading imports.
Candidate availability and statement hashes are checked before returning names.
`model.warmup` uses the fixed query `True`; actual-goal lazy expansion remains part
of query cost. Query work defaults to 10,000 heartbeats. Initialization is separate
and its threads/memory are controlled by the surrounding Lean process/job.
For competing methods in one process, call `model.freshCache` on a fixed warmed
base before any goal queries. This shares immutable preparation data while giving
each method independent lazy refinement; one method cannot warm another on its
evaluation goals.

Combine it with sparse retrieval using
`JevSelector.fuse #[idx.targetSelector, model.selector {}]`. Numeric scores encode
rank rather than probabilities. Fusion checks candidate eligibility from live
signatures, so that check does not wait for unfinished theorem bodies. Constituent
selectors remain responsible for their own access behavior. CPU profiles accept `--method structural` and
`--method structural-target`; `structuralInitMs` records creation plus fixed warmup
separately from artifact loading and query time. The profile's statement index is
used to choose repeatable query types; pure structural retrieval does not fit it.
Native validation and full-Mathlib timing profiles pass on the research branch.
The replayed 134-location development comparison measured 63 successes for the
sparse/structural fusion, 57 for sparse, 63 for neural, and 64 for neural/structural,
all with Jev proof-state guidance. Fusion improves the CPU baseline but has not
beaten the strongest neural reference; see [research results](notes/research-results.md)
for paired uncertainty, exposure limitations, and costs.

The experimental `StructuralIndex.create .rewrites` mode indexes both sides of
equalities and iff statements, then matches bounded goal/context subexpressions.
It returns standard premise suggestions for any downstream tactic set. Forward
matches get twice the specificity weight of backward matches; each name receives
only its strongest match. `StructuralConfig` bounds distinct visited expressions
(256), pattern queries (64), traversal depth (8), and propositional hypotheses
(8), in addition to the total heartbeat limit. Duplicate subexpressions are
visited once, including application function heads and arguments. The same
availability, state, and cache-isolation rules apply.
Profile this mode with `--method rewrites` or sparse fusion with
`--method rewrites-target`. Native boundary tests and fixture profiles pass.
Use `--method structural-rewrites` for conclusion/rewrite fusion and
`--method structural-rewrites-target` to add the sparse target source. These use
flat rank fusion, initialize both signature indexes, and record their combined
initialization cost separately. Profiles explicitly request and report 100
suggestions. Full-Mathlib profiling of `fab11ad` measured rewrite lookup at
16.0 ms median / 75.1 ms p95, with 28.3 s initialization. Conclusion/rewrite
fusion measured 67.1 / 200.2 ms; adding sparse retrieval measured 209.7 / 361.5 ms.
Both combined modes took about 56 s to initialize, with a shared serial-profile
peak of 5.14 GB. These timings use 32 fixed statement types with three repeats.
The independently replayed 34-location proof screen was negative: CPU fusion
with rewrites solved 13 versus 16 for its control; neural fusion with rewrites
solved 14 versus 16 for its control; signature-only solved 14. This is an
experimental option, not the strongest measured configuration. Its
[design note](notes/experiment-08-design.md) records the fixed recipe.

`Index.validateHoldouts owners` rejects owners contributing to fitted statistics.
Call it with **every evaluation owner** before benchmarking. Use
`Index.validateEnvironment` during warmup to check available imported statements.
Querying always checks availability, caller filters, and imported candidate type hashes.
Current-file theorems use their live statement features, even when the prepared
catalog contains the same names. This supports edited files and fresh elaborations
with different auxiliary names or instance terms. Set `includeCurrentFile := false`
to exclude these premises entirely. The selector deduplicates and obeys
`maxSuggestions`. Unavailable later theorems cannot be returned.

## Guided dependency traversal

The experimental `DependencyGraph` supplies signature-only backward/forward
dependencies and a bounded `guided` selector that decorates any standard CPU
selector. An injected ranker chooses traversal directions using printed types
and the goal context. With JevHammer's selector-guidance API, these decisions
share the proof search's Jev budget. No additional neural model is required.
See [the graph API and limitations](docs/dependency-graph.md). Proof-quality
improvement has not yet been measured.

## Resources, artifacts, and tests

On Linux the CLI automatically establishes a **24 GB, zero-swap cgroup** around
the complete process tree. `--memory-limit` accepts at most 32 GB. Elsewhere use
a bounded container/job and `--external-memory-limit`; this records an explicit
externally managed limit, not a claim that Python enforced it. Preparation runs
one Lean process at a time. Query options bound per-symbol postings; setting
`maxPostingsPerSymbol := 0` selects exhaustive traversal.

Artifacts include portable `index.json`, SHA-256, extraction records, source and
dependency fingerprints, recipe, resolved eligibility, and preparation resource
measurements. The index is tied to its Lean version and statement snapshot.
Treat artifacts as trusted data and verify their published checksum before use.
No automatic fallback hides missing, incompatible, or overlapping artifacts.

```sh
# From this repository, inside a bounded job:
bash tests/run.sh --external-memory-limit
```

For repeatable CPU latency measurements (not proof coverage):

```sh
jevselector profile --modules MyLibrary --index artifacts/full/index.json --output runs/profile
```

Use `--method target` or `--method ensemble` to profile the research candidates.
To enforce a 16 GB bound, append `--memory-limit 16000000000`. If other local
services participate, place them and the CLI inside one shared bounded job.

This measures cold loading and repeated queries on evenly spaced theorem types,
excluding the query theorem itself. For quality measurements use JevHammer's
source-location benchmark.

See [initial validation](docs/validation.md), [artifact and algorithm details](docs/artifacts.md),
[contributing](CONTRIBUTING.md), and [research plans](notes/design.md).
Licensed under the [Apache License, Version 2.0](LICENSE).
