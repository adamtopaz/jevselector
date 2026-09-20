# Candidate: show Jev the reachable neighborhood

This proposal was recorded during the frozen first signature-graph proof screen.
It does not modify that run. The complete paired results and independent replay
still determine whether its candidate advances. No individual failed proof goal
was read to form this proposal, and no improvement is claimed here.

The current selector supplies a seed's printed type, the two bounded neighborhood
sizes, and the choices none/backward/forward. The first 16 recorded selector
requests contained 128 frontier nodes. Mechanical response analysis found 105
backward choices, 21 no-expansion choices, and two forward choices; 13 chosen
expansions had empty neighborhoods. These are partial behavior measurements,
not final coverage or causal evidence. Counts must be replaced or supplemented
by the complete screen before interpreting them.

A constant's type can explain its mathematical role while revealing little
about which lemmas reference it. A bounded preview would let Jev assess the
actual available destination statements. This is a hypothesis about the choice
representation, separate from changing graph edges, frontier selection, or
proof-search budgets.

## Isolated representation change

Add opt-in preview bounds to `GraphConfig`, initially three destination
statements per nonempty direction and 480 printed characters per statement.
Keep the original zero-preview configuration available. Use the same bounded
neighborhoods and deterministic base-rank/seed-overlap ordering already used
for edge selection. Reuse that ranking when expanding the chosen direction;
do not introduce a second ranking rule or alphabetic preview bias.

Each preview entry carries a constant name, printed type, and explicit type
truncation flag. The action carries the full bounded neighborhood count and a
flag indicating omitted preview entries. For no expansion the preview is empty.
The question should explain that previews are examples of the available
statements reached by that action, and ask whether they can supply useful
premises for the current target and hypotheses. The model still chooses only
among program-generated actions; it creates no names or proof text.

Retain one round, eight frontier nodes, the same forward/edge/visited bounds,
and one shared-budget callback. Printing and candidate validation stay inside
the existing query heartbeat and proof-search time budgets. Do not add model
calls during warmup, raise the three-call allowance, or change the tactic set.
The constant's type remains present, so backward steps through intermediate
concepts remain interpretable even when few destinations are final premises.

Previews must reflect the live environment. Use signature-only lookup, exclude
inadmissible final-premise examples, and honor the caller filter before taking
the display prefix. A private or caller-rejected destination may serve as an
internal traversal node under the existing rules but must not be advertised as
an admissible output premise. Save and restore state around printing, caller
filters, and callbacks. Mark any mismatch between full traversal count and the
number of display-eligible destinations explicitly rather than implying a
preview exhausts the neighborhood.

## Evidence required before another proof screen

Synthetic checks should establish that forward previews contain the expected
referencing statements, backward previews come from the signature rather than
the proof body, and unavailable/private/caller-rejected declarations never
appear as premise examples. Exercise truncation, empty neighborhoods, invalid
rankings, current-file rollback, and state-mutating callbacks/filters. Verify
that zero-preview mode preserves the current request and output behavior.

Run the same fixed full-library CPU cost queries with native plugins. Compare
ordered outputs under fixed direction callbacks: adding information to the
model's payload alone should not change deterministic graph traversal. Report
payload bytes, printing cost, initialization, query latency, and memory. Actual
Jev latency remains a separate cost to measure in proof trials.

If cost is viable and the completed first screen warrants this isolated test,
freeze a matched pilot with the CPU control, original graph representation,
preview graph representation, and the stronger neural control configurations.
All use the same Jev proof-state search and shared budgets. Preserve both
neural controls when their relative strength remains uncertain. Only completed,
independently replayed results determine promotion; the reserved evaluation
cohort stays untouched during method development.

Other changes, such as additional rounds, proof-dependency edges, different
frontier selection, or deferring selector guidance until after CPU-only proof
attempts, require separate hypotheses and comparisons. They are not part of
this representation ablation.

## Draft implementation during the frozen run

The root research worktree now has an opt-in implementation and synthetic tests.
The benchmark continues to use its clean, pinned `d6f4e25` checkout. The draft
factors out the existing neighbor ordering, reuses the exact ranked edges for
previews and expansion, and adds no preview fields when the option is zero.
Caller-filtered display truncation and metadata are covered by drafted fixtures.
Compilation, the full offline suite, native full-library output equality, and
cost measurement have not run yet: the live proof job has priority in the
single 16 GB resource scope. These drafts are not benchmarked improvements.


## Completed first screen and offline validation

The original representation's complete screen is negative: graph 14/34 versus
CPU 16/34 and the stronger neural arm 15/34, all successful proofs replayed.
The final direction counts are 326 backward, 50 none, and eight forward across
384 nodes. Fifty selector calls cost 20.900 seconds and left 24 state calls;
CPU control made 41 state calls. The paired outcomes and uncertainty are in
`notes/research-results.md`. The original configuration is not promoted.

After that run and its services stopped, the preview implementation compiled
and passed focused graph checks plus the complete offline suite. All 29 Python
tests and native/artifact/profile checks passed. The single 16 GB zero-swap
validation scope peaked at 890,617,856 bytes, with no memory events and no model
calls. The report is `docs/graph-preview-validation.json`. Full-Mathlib native
ordered-output equality and cost profiling are still required before freezing
another proof screen. No preview proof trial has run.

## Native full-library cost and compatibility checks

Both serial native profiles completed under benchmark `3969df5`, using selector
`397bef6`. The zero-preview version preserves all **384** prior ordered query
results, callback/choice counts, payload sizes, and errors. The three-preview
version preserves all **384** zero-preview ordered results and callback/choice
counts; only the intended payload content and measured timings change. All modes
have zero errors, and each of the 32 statement groups is stable across its three
repeats. These are injected direction decisions, not actual Jev quality results.

For three previews, no-expansion/forward/backward median costs are
**247.59/243.03/247.80 ms**, with p95 **386.87/382.96/386.73 ms**, including the CPU
base but excluding Jev latency. Corresponding zero-preview costs are
**123.45/200.97/124.22 ms** median and **246.50/351.71/225.43 ms** p95. Median
choice-plus-question payloads increase from **5,958.5 to 16,855.5 bytes**; the
separate goal/context is not included in these byte counts. Preview generation
requires considering both directions before model selection, including when
no expansion is eventually chosen.

Full graph initialization remains about **14.7 seconds**, structural setup
**6.6–7.3 seconds**, with artifact loading measured separately. The sequential
batch peaked at **8.91 GB** in one 16 GB zero-swap scope, with no memory events,
no neural service, no model calls, and no proof trials. Memory peaks are cumulative
within that shared scope. Benchmark reports are
`docs/cpu-selector-profile-graph-v5.json` and `...-v6.json`.

The preview option exceeds the provisional 200 ms CPU p95 target. A small matched
proof screen can test whether its extra evidence earns that cost; no superiority,
coverage improvement, or promotion is established by these profiles. Retain the
CPU control, original graph representation, preview representation, and both
neural configurations under unchanged proof-search budgets. Re-admit the same
34 development locations after pinning adapters, and freeze that protocol before
new model calls. Reserved evaluation stays untouched.
