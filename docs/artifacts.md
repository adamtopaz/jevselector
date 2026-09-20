# Schema 1 and initial algorithm

`index.json` stores `schema`, `leanVersion`, theorem `declarations` (name, module,
Lean structural type hash, unique type constants), positive symbol `weights`,
`eligible` names, resolved `excluded` names, and `provenance`. Provenance includes
the exact holdout input/digest (or null), recipe, source/dependency snapshot,
preparation code digest, and content-derived artifact identity. `index.sha256`
covers the complete serialized artifact; the identity is a recipe/input identity,
not a replacement for that checksum. `report.json` measures preparation and
records incomplete runs explicitly. Output directories cannot be overwritten.

The optional `publicConstants` flag permits definitions/constructors in the
catalog. `candidateOnly` lists non-theorem candidates outside held-out owners;
these are disjoint from `eligible` and `excluded`. They do not affect IDF, mean
length, or proof training. Held-out public types remain candidates through the
existing `excluded` policy. Old artifacts omit the new fields and retain their
theorem-only behavior. The loader validates the three-way catalog partition.
Current-file supplementation follows the same catalog policy.

No proof body, proof dependency, trace, or external model contributes to schema 1.
For eligible theorem count N and document frequency df(s), symbol weight is
`1 + log((N+1)/(df(s)+1))`. Holdouts are removed BEFORE N and df are computed.
Their public statements remain in the catalog for legitimate later retrieval.
Symbols absent from fitted statistics receive the fixed weight 1 at query time.
Serialized feature names are opaque strings, matched against the same printer
at query time. They are never parsed with `String.toName`: hygienic/internal
constant names can fail identifier parsing and collapse to the anonymous name.
This differs from actual public premise names, which are resolved and checked
against the current environment.

Queries union constants from the target, hypothesis types, and local definition
values. A sparse inverted index accumulates symbol weights; each premise's score
is divided by the square root of its symbol count. Stable name ordering breaks
ties. Common-symbol postings are sampled evenly up to 20,000 per query symbol by
default, before environment filtering. This bounds work but can reduce recall;
set the cap to zero for exhaustive lookup. The caller filter runs before the
final maximum is applied. Scores are compressed into [0,1), not probabilities.
Current-file supplementation uses the same type-only features.

The research branch supports optional target/context weights and pivoted length
normalization in `QueryConfig`. The latter's mean length is computed at load time
using only `eligible` statement rows; excluded statements do not contribute.
These options reuse schema 1 and do not change the default ranking. The selector
configuration is a separate part of experiment provenance, in addition to the
artifact identity. `Index.ensembleSelector` fuses the default and target-weighted
rankings without fitting another artifact.

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

The base index has no proof-frequency statistics, graph traversal, Jev reranking,
query result cache, or binary/memory-mapped representation. Experimental direct
proof-neighbor statistics live in a separate companion artifact described below.
Compare end-to-end verified proof coverage, not only retrieval recall.

Preparation/profile Lean processes rely on the aggregate cgroup/job limit.
A separate Lean allocator limit is disabled because memory-mapped whole-library
imports can exceed it even when resident memory is small.

The CLI obtains `lake setup-file` metadata and loads its native plugins when
elaborating generated files. Plain `lake env lean file.lean` does not reproduce
that setup; use `lake lean file.lean` or ordinary Lake builds in downstream
projects to benefit from native metaprogram execution.

## Experimental dependency companion

`dependencies.json` has its own schema-1 format: Lean version, the linked statement
artifact identity, one dependency row per exact eligible owner, a unique premise
catalog with statement hashes and label-frequency weights, and provenance.
`dependencies.sha256` covers its bytes. `jevselector verify` recognizes either
artifact directory. Preparation imports all requested modules so proof values
can be accessed; it fails if an eligible proof is unavailable or contains an
admission. It never reads excluded proof values or recursively opens referenced
definition/helper bodies. Thus dependencies hidden inside helpers are omitted.

The optional `publicLabels` flag broadens direct labels to permitted public
constants. It never broadens proof owners: the extractor verifies each eligible
owner is an original theorem before obtaining its value. Definitions can be
returned as labels without opening their bodies or fitting them as examples.
This option is independent of the statement catalog and recorded in provenance.

All owner-set checks precede fitting label frequencies. The loader independently
rejects missing, duplicate, or ineligible examples, mismatched statement identities,
uncataloged/duplicate labels, and invalid weights. Label weights are
`1 + log((N+1)/(df+1))`, with N the number of eligible examples and df the number
of those examples containing the label. Held-out theorem statements can be labels
in other eligible proofs, but their own proofs remain excluded from examples.
The runtime checks both availability and the caller filter before truncation.
Available imported premise hashes are checked; earlier current-file labels use
the actual live statement, as for the base selector.

The dependency report records extraction time, example/edge counts, size, memory
events, and the exact statement-index checksum and source snapshot. Holdout
validation delegates to the linked statement index, whose eligible set must
equal the dependency example set. Training-example lookup is a separate API from
premise lookup: examples may be unavailable at a goal, but predicted premises
may not. No proof bodies are queried at runtime.

## Experimental usage companion

`usage.json` contains the linked statement identity, exact eligible example
owners, feature vocabulary, and premise records. Each premise stores its
statement hash, log prior, log normalizer, and retained positive feature
corrections indexed into the shared vocabulary. `usage.sha256` attests the
serialized model. The default smoother has mass 20 and retains the 64 largest
corrections per premise; the full normalizer remains unchanged by pruning.

Preparation checks all owners and labels before counting. The CLI additionally
requires the dependency artifact's recorded statement-index checksum to match
the actual input bytes. Fitting reads only the two immutable artifacts, records
their checksums and fitting-code hash, and rejects changes during the pass.
It does not require a new Lean extraction or inspect any additional proof.

Warm queries accumulate feature corrections through bounded sparse postings,
then add each touched label's prior and query-length normalizer. Unknown query
features are ignored. Returned scores are exponential differences from the best
returned score, preserving rank without claiming calibrated probabilities.
There are no popularity-only results when a query has no matching postings.
The loader rejects duplicate/missing/ineligible examples, invalid feature IDs or
weights, excessive feature counts, and incompatible statement identities.
Availability, caller filters, and imported type-hash checks precede truncation.
