# Hypothesis: defer premise guidance until the CPU base fails to finish

This design is recorded during the frozen destination-preview comparison. It
uses the preceding completed graph screen and a generic search-flow review,
not individual failed proof goals. It does not alter the running experiment.

In the completed screen, the graph arm spent 50 selector calls and made 24
proof-state calls, versus 41 state calls for CPU control. Graph retrieval took
28.954 seconds in total, including 20.900 seconds in selector requests. It solved
14/34 versus CPU 16/34. Premise reranking also shares the search's three-call
allowance. Model work happens before trying the selected-premise finisher, even
when the native candidate ordering might already suffice.

## Proposed optional search policy

After the existing cheap closing and preparation phases, first retrieve premises
from the supplied base selector and try the configured premise-finishing tactics
without selector-factory guidance or ordinary Jev premise reranking. If this
closes the goal, skip those model calls. Otherwise restore the saved Lean state,
perform the usual guided selection, and continue through the existing finisher
and Jev-guided proof-state search.

Make this an explicit opt-in JevHammer configuration, default false. It applies
to both injected selector factories and ordinary `guidePremises` reranking. A
method with neither kind of premise guidance should keep its current execution
path and avoid redundant work. The public generic tactic set and base selector
remain supplied by the caller; this policy introduces no Mathlib dependency.

Use the same runtime start time, statistics reference, ranker, call limit, and
outer heartbeat budget for both stages. The unguided attempt consumes goal time
and tactic work. It must never reset a deadline, add model calls, turn off later
proof-state guidance, or carry speculative assignments into the guided stage.
Record attempts and successes of the early premise-finishing pass separately,
and include all retrieval and tactic costs in existing totals.

For an initial implementation, it is acceptable to query the base selector again
if the early finisher fails. That overhead must be timed and reported. Reusing a
cached ranking would need a stronger contract: selectors may inspect the goal,
configuration and caller filter, and factories may use suggestion scores as well
as names. Do not cache only normalized names and silently change those semantics.

## Validation and comparison

Synthetic fixtures should prove that a CPU-premise finish skips both factory
callbacks and ordinary premise-reranking calls; unsuccessful CPU attempts restore
state and proceed to the guided path; call and wall budgets span both stages;
failures remain atomic across original goals; default false retains prior
behavior; and unguided methods are unaffected. Check public tactic syntax and
both the standalone library and benchmark Lean versions before pinning it.

For future proof trials, enable the same scheduling option for all matched arms,
including the strongest neural controls. Retain an original-schedule comparison
where needed to isolate the schedule itself. A gain against an unchanged weaker
reference would not establish a better selector: the neural reference must be
allowed the same opportunity to skip unnecessary premise guidance. Keep the
same six-second/three-call budgets and independently replay every success.

This is a separate hypothesis from showing destination previews. Complete the
current frozen screen first. No implementation, timing improvement, or coverage
improvement is claimed by this design note.

## Implementation and validation

The opt-in `deferPremiseGuidance` implementation passes the full JevHammer build,
native regression suite and independent consumer on Lean 4.34.0 and identical
Lean sources on benchmark Lean 4.33.0. It remains false by default. Tests exercise
factory and ordinary-reranking avoidance, default/unguided compatibility, partial
progress restoration, shared calls and clock, later state guidance, whole-goal
atomicity and public tactic syntax. No real model calls were made.

The public-version checks took 6.14 / 5.17 / 0.62 seconds for build / native /
consumer, peaking at 2.25 GB. The compatibility checks took 4.57 / 3.37 / 0.62
seconds and peaked at 0.45 GB. Both serial jobs used a 16 GB zero-swap scope with
no memory events. Source hashes and full audit are published in JevHammer's
`docs/deferred-guidance-validation.json`.

The preceding preview proof screen is complete: CPU 16/34, both graph variants
14/34, neural native 13/34, neural reranked 14/34; all 71 successes replayed. No
preview promotion follows. The scheduling option still has no live proof result.
