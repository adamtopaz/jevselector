# Signature-only eligibility in composed selectors

Source review during the frozen rewrite-source pilot found that `fuse` calls
Lean's `LibrarySuggestions.isDeniedPremise`. In Lean 4.33 this calls
`Environment.find?`, which waits for a theorem's complete constant information,
including its body. The deny policy only needs the declaration name, attributes,
module, and type. Structural retrieval already uses a signature-only adaptation,
but its fusion wrapper reintroduces the full lookup.

Share that existing policy as `isDeniedSignature` in the foundational features
module, and have fusion obtain available types with `findConstVal?`. Preserve
the same deny lists, availability checks, caller filters, deterministic ranking,
and state isolation. This makes the wrapper itself signature-only; arbitrary
constituent selectors still control their own lookups. No claim is made that
all existing sparse/dependency selectors avoid waiting on every body.

Add a synthetic regression that commits a theorem signature while withholding
its body, returns that name from a constituent selector, and requires fusion to
return before the body is supplied. It then completes the theorem and restores
the test environment. Bound the test with a process-group timeout so a regression
cannot leave blocked Lean workers behind. Existing deny/filter/cache tests still
apply to the shared policy.

This correction is drafted independently of individual benchmark goals. The live
pilot stays pinned to `fab11ad`; it must not pick up the draft. After the run and
services exit, first execute the new regression against the old compiled package
to establish the failure, then rebuild and run the regression and existing suites.
Until then the draft is unvalidated and carries no timing or proof-coverage claim.

Validation is now complete. Against the previous compiled package the synthetic
regression exceeded its 30-second bound. A repeated diagnostic recorded that the
block occurred inside fusion, after committing the signature and before supplying
the body; its process group was terminated. The corrected build completes the
same regression, including body completion and environment restoration.

All 19 Python tests, native selector/holdout/cache/filter suites, and ten fixture
profile modes pass. The launcher initially supplied `--threads 2` to the Python
usage-fitting command, which has no such flag; the already-passed checks were
retained and the remaining suite resumed without that flag. Lean still used two
threads. Both phases ran serially under 16 GB with zero swap. This is an
interactive correctness/responsiveness fix, with no proof-coverage claim. The
completed rewrite screen continues to describe its original `fab11ad` package.
