# Schema 1 and initial algorithm

`index.json` stores `schema`, `leanVersion`, theorem `declarations` (name, module,
Lean structural type hash, unique type constants), positive symbol `weights`,
`eligible` names, resolved `excluded` names, and `provenance`. Provenance includes
the exact holdout input/digest (or null), recipe, source/dependency snapshot,
preparation code digest, and content-derived artifact identity. `index.sha256`
covers the complete serialized artifact; the identity is a recipe/input identity,
not a replacement for that checksum. `report.json` measures preparation and
records incomplete runs explicitly. Output directories cannot be overwritten.

No proof body, proof dependency, trace, or external model contributes to schema 1.
For eligible theorem count N and document frequency df(s), symbol weight is
`1 + log((N+1)/(df(s)+1))`. Holdouts are removed BEFORE N and df are computed.
Their public statements remain in the catalog for legitimate later retrieval.
Symbols absent from fitted statistics receive the fixed weight 1 at query time.

Queries union constants from the target, hypothesis types, and local definition
values. A sparse inverted index accumulates symbol weights; each premise's score
is divided by the square root of its symbol count. Stable name ordering breaks
ties. Common-symbol postings are sampled evenly up to 20,000 per query symbol by
default, before environment filtering. This bounds work but can reduce recall;
set the cap to zero for exhaustive lookup. The caller filter runs before the
final maximum is applied. Scores are compressed into [0,1), not probabilities.
Current-file supplementation uses the same type-only features.

`validateHoldouts` rejects any evaluated owner or named child present in eligible
training rows. Owners absent from the exported scope did not contribute and are
allowed. Non-theorem owning definitions cannot contribute proof information in
this version. Future proof-sensitive recipes must strengthen auxiliary ownership
tracking before accepting these artifacts as proof-disjoint.

The loader checks version, schema, positive weights, catalog uniqueness, and
training eligibility consistency. Runtime type hashes are compatibility checks,
not cryptographic attestations. The benchmark still kernel-checks every proof.
Full-library artifacts are valid deployment artifacts and are rejected by the
benchmark adapter when fitted rows overlap its evaluation declarations.

The CLI fingerprints local source files and resolved dependency source trees.
Logs and export configuration may contain preparer's machine paths; only the
index and checksum are needed for deployment. No absolute path is needed to
load or query the index. Do not distribute credentials in project manifests.

The initial version has no learned proof-frequency statistics, graph traversal,
Jev reranking, query result cache, or binary/memory-mapped index. These are future
experiments; compare end-to-end verified proof coverage, not only retrieval recall.
