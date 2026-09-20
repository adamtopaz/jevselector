# Per-extraction dependency metadata cache

The full-Mathlib Bayes preparation measured 762.15 seconds for extracting
1,536,554 direct theorem-label edges from 254,885 eligible proof owners. Bayes
fitting itself took 18.40 seconds. The complete pipeline exceeds the provisional
ten-minute target, so extraction deserves investigation independently of the
ongoing proof-quality screen.

The existing loop checks the deny policy, original declaration kind, and type
hash for every referenced name in every eligible proof. Common constants repeat
across many owners. Cache both accepted JSON label records and rejected-name
decisions in a local map keyed by constant name. The environment and label policy
are fixed for the duration of one export. Do not cache proof values, traverse
referenced bodies, or relax owner eligibility. Exclude self references before
consulting the cache, and preserve the existing sorted output order.

This is intended as a semantics-preserving preparation optimization, not a new
selector or a proof-coverage improvement. It was kept separate from the frozen
Bayes proof comparison, which is now complete with no candidate promotion.

After the proof run and its services exit, build and compare fresh fixture
exports against the retained uncached JSONL records, byte for byte. Exercise both
theorem-only and public-constant label policies, module-system theorem handling,
held-out owners, private helpers, and the existing invalid-owner rejection. Then
measure full-library extraction using the same statement index and compare its
entire raw JSONL output against the completed uncached run. Record CPU time,
wall time, memory, and any difference. Do not claim a speedup before measuring it.

## Fixture validation

After the complete Bayes collection and all 70 successful-proof replays, the
cache compiled and three fresh raw exports matched retained pre-cache exports
byte for byte: `SelectorFixture` and `ModernFixture` with theorem-only labels,
and `CatalogFixture` with public-constant labels. The native dependency/catalog
checks passed, and the deliberately corrupted definition-owner index was still
rejected. The full integration suite also passed: 29 Python checks, native
selector tests, and 16 profiling paths. The shared validation job peaked at
341,233,664 bytes with no memory events under 16 GB and zero swap.

Full-Mathlib output equality and performance measurement remain pending. No
speedup is claimed from these small fixtures.
