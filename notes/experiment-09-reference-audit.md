# Reference audit: repeat premise reranking with matched catalog warmup

Recorded while the frozen 134-location structural comparison is running. This
does not change that run's methods, admission, parameters, or interpretation.

The initial current-harness reference gave neural retrieval with Jev premise
reranking 11/34 successes, and retrieval without reranking 15/34. However, the
first adapter warmed imported statements only; current-file statements could be
embedded inside the goal clock. Its second run reused the first service's cache.
The published benchmark report already notes that the 48.814-to-10.788-second
retrieval-time change prevents treating this as a clean reranking ablation.

Later `Research.neuralWarm` comparisons corrected the initialization policy by
warming both imported and earlier current-file statements outside goal timing.
They have so far disabled premise reranking. Consequently, the initial 11/34
result does not establish that reranking is inferior with the stronger warmup
policy. Historical experiments also found neural plus Jev premise reranking
competitive, so the final reference must not discard it on this confounded result.

After completing the running comparison, perform a fresh-service development
comparison with matched initialization and two factors:

| Premise source | Native order | Jev premise reranking |
|---|---|---|
| Selected CPU candidate | Jev proof-state guidance | Jev premise and proof-state guidance |
| Warmed neural reference | Jev proof-state guidance | Jev premise and proof-state guidance |

Choose the CPU source from the completed full-development comparison: highest
on-time replayed coverage, with lower retrieval cost breaking a tie. Freeze that
choice before collecting this next comparison. Use the existing 34-location
development pilot for screening, all its locations retained. No reserved
evaluation outcome may influence the choice. If this establishes a stronger
neural reference, carry it forward into the larger matched comparison before
claiming an improvement over the strongest baseline.

Keep the six-second goal budget, three **shared** Jev calls, 100 retrieved names,
unchanged tactics, and current structural cache isolation. Only the reranked
arms enable `guidePremises`. All calls, including premise ranking, consume the
same accounting and time budget; failed rankings and API errors stay in results.
Do not accidentally apply a global `guidePremises := false` override to the
reranked methods. Verify actual configuration and premise/state call counts.

The four-arm pilot would have 136 trials, at most 408 Jev requests and 4,000,000
reported input tokens, with a fresh CPU neural service. Keep the shared 16 GB,
zero-swap bound, two threads, serial modules, and independent proof replay.
Re-admit identical source locations after any adapter changes. Publish all four
arms and paired uncertainty; an exposed development pilot is not final evidence.

This audit is a requirement for a stronger final comparison, not a claim that
reranking will improve either source. The bounded rewrite-pattern mode remains
a separate candidate requiring full-library cost profiling and matched proof
evidence. Do not combine it into this ablation without explicitly freezing a new
protocol before collection.
