# Initial validation (2026-09-18)

This is infrastructure and CPU-cost validation, not a live Jev proof-quality
comparison. Lean 4.33.0, the pinned Mathlib snapshot, two Lean worker threads,
and one 24 GB zero-swap process tree were used. Whole-library imports and
compiled caches were already available; preparation figures exclude downloading
the Lean toolchain and Mathlib cache.

The independent fixture exercises production preparation, declaration/module
exclusions before fitting, unknown holdouts, current-file supplementation,
unavailable premises, caller filters before truncation, changed statements,
artifact checksums, and full-data overlap rejection. GitHub CI runs the small
fixture without credentials or Mathlib.

An initial whole-Mathlib extraction produced 255,050 public theorem statement
rows. A 32-location held-out Mathlib cohort excluded 46 declarations/helpers
(21 theorem rows). The resulting schema-1 index was about 156 MB. No proof bodies
or external model outputs were used.

On that index, 16 evenly spaced theorem types queried three times each gave:

| Execution | Queries | Median | 95th percentile | Cold index load |
|---|---:|---:|---:|---:|
| Lean interpreter, lazy candidate filtering | 48 | 700 ms | 1,918 ms | 14.1 s |
| Native selector plugins | 48 | 46.6 ms | 104.1 ms | 3.7 s |

Both profiles used the same artifact, query types, posting cap (20,000 per
symbol), and maximum suggestions (100). The query theorem itself was excluded.
Native execution is now the normal Lake/CLI path. This small latency sample is
not a guaranteed bound and says nothing about proof coverage. Cold loading is
separate from warm query latency; keep the loaded index between goals.

Reproduce latency with:

```sh
jevselector profile --project PATH_TO_PROJECT --modules Mathlib \
  --index artifacts/heldout/index.json --samples 16 --repeats 3 --output runs/profile
```

For actual quality use [jevhammer_benchmark](https://github.com/adamtopaz/jevhammer_benchmark)
with fixed source locations, excluded owners, Jev guidance, and independently
verified certificates. Matching the strongest neural-selector pipeline remains
an unproved research objective.
