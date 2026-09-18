# jevselector

Portable premise-selector preparation and CPU retrieval for Lean. Implements
Lean's standard `Lean.LibrarySuggestions.Selector`; no Mathlib, JevHammer,
Python runtime, neural model, or network service is required for **querying**.
The preparation CLI uses Python's standard library and Lake.

The initial algorithm indexes constants in theorem **types** and ranks weighted
symbol overlap with the goal and local context. It never reads proof bodies.
This is an inspectable baseline for further experiments, **not yet a demonstrated
replacement for the strongest neural-selector/JevHammer pipeline**.

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

## Prepare any library

Run from a Lake project importing the desired library:

```sh
jevselector prepare --modules MyLibrary --scope MyLibrary --output artifacts/full
jevselector verify artifacts/full
```

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

`Index.validateHoldouts owners` rejects owners contributing to fitted statistics.
Call it with **every evaluation owner** before benchmarking. Use
`Index.validateEnvironment` during warmup to check all available statements.
Querying always checks availability, caller filters, and candidate type hashes.
It supplements the artifact with earlier current-file theorems, deduplicates,
and obeys `maxSuggestions`. Unavailable later theorems cannot be returned.

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

This measures cold loading and repeated queries on evenly spaced theorem types,
excluding the query theorem itself. For quality measurements use JevHammer's
source-location benchmark.

See [artifact and algorithm details](docs/artifacts.md),
[contributing](CONTRIBUTING.md), and [research plans](notes/design.md).
Licensed under the [Apache License, Version 2.0](LICENSE).
