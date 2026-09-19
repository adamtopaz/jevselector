# Candidate design: broaden the premise universe

Source-level audit, 2026-09-19, without inspecting individual benchmark failures.
The pinned neural adapter's `Cloud.getImportedPremisesCore` and
`getUnindexedLocalPremises` admit public constants using `isDeniedPremise` without
requiring `wasOriginallyTheorem`. Our statement exporter requires both the
not-denied check and `wasOriginallyTheorem`; direct dependency extraction also
restricts labels to theorems. The two selectors therefore have different premise
universes. This is a possible coverage limitation, not an explanation established
by the existing benchmark scores.

References: pinned [premise-selection Cloud adapter](https://github.com/hanwenzhu/premise-selection/blob/5d24284dab7d61e3b80bfd5efc6bf2597bafe97b/PremiseSelection/Cloud.lean)
and Lean's [premise deny filter](https://github.com/leanprover/lean4/blob/v4.33.0/src/Lean/LibrarySuggestions/Basic.lean).
Definitions can be useful as explicit unfolding premises, and public constructors
can be useful for application. The generic consumer already filters suggestions
against the actual environment and can attempt them through its tactic set.

An explicit opt-in catalog of public constants is a general-purpose hypothesis.
Keep three concepts separate: catalog candidates, examples fitted into type-only
statistics, and owners whose proof values can be inspected. Broadening candidates
must NOT silently cause dependency extraction to read definition bodies. Initially
keep theorem-only eligible proof owners, exact owner exclusions, and direct-body
traversal; permit public non-theorem constants as labels occurring in those
eligible proofs. Public types remain available for compatibility checking.

A minimal controlled first test can broaden candidate/label coverage while keeping
eligible theorem training owners and the voting/usage formula fixed. Preserve
original recipes and emit an explicit catalog/label policy in provenance. Native
loaders must validate the intended proof-owner set, not infer it from predicted
label names. Non-theorem held-out owners still require admission and availability
checks; they must not start contributing proof information through this change.

Measure candidate counts, extra preparation/query/memory costs, and paired verified
proof coverage. Do not tune by inspecting which specific failed goals use missing
definitions. Test this independently from structural features or altered Jev
budgets. If it helps, consider generalizing the type-statistics eligibility policy
separately, with a documented schema and explicit tests for every holdout mode.
