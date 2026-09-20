# Signature graph initialization costs

The first full-Mathlib graph cost screen uses frozen selector `66197c1` and
benchmark `2ddc190`. It has not yet produced any query rows after several
minutes. A live process check confirms CPU work, not an absent or restarted job.
No claim about the exact phase or cause follows from that observation: the
initial profile prints only after loading, validation and graph construction.

Code review found an avoidable cost in reverse-edge construction. The expression
`edges.insert dependency ((edges.getD dependency #[]).push name)` retains the
map holding the old array while appending to that array. On dense symbols this
can force repeated array copying. Lean's own `Array.groupByKey` uses
`HashMap.alter` to update the grouped array; use that same ownership pattern here.
The intended edge order, filtering and traversal behavior remain unchanged.

The root selector worktree contains this one-line optimization draft. Do not
build it or change the frozen benchmark checkout while the old cost screen is
live. After that process is terminal, retain its evidence, validate graph and
unresolved-proof regressions, and compare old/new canonical graph snapshots.
Then pin the validated optimization for a fresh, distinctly named cost run.
Add explicit phase progress so loading, environment validation and graph
construction costs can be distinguished. Keep the 16 GB aggregate cap and
zero swap; no parallel heavy job. No proof goals or held-out results motivate
this change.

## Completed differential check

The original Mathlib job reached its 600-second timeout before recording a
query. Its output is retained as `cpu-selector-profile-graph-v1`, with no
memory events and zero proof/model calls. The pre-query phase remains unknown.

After that process stopped, old and optimized constructors produced
**byte-identical canonical graphs** over the Lean import environment: 54,484
entries, 10,521 forward keys, and 28,767,249 serialized bytes. SHA-256:
`487a7caa8fddce076299ec69e9a18395ce35fad0dee9bf5b129515d5b96c4eed`.
Graph and explicitly unresolved-proof regressions passed. The constructor
timings were 7,410 ms before and 3,778 ms after, one process each; this is a
small-environment diagnostic, not a measured Mathlib speedup. Peak memory was
511,315,968 bytes under the 16 GB zero-swap cap, with no memory events.

The evidence is in `docs/graph-initialization-validation.json`. To produce the
same canonical snapshot in either revision, run `tests/tools/GraphSnapshot.lean`
with `JEVSELECTOR_GRAPH_SNAPSHOT` set to an output path. The next Mathlib attempt
will use an explicitly pinned optimized revision and separate phase progress.
