module
public meta import JevSelector.Index
public meta section
namespace JevSelector
open Lean Meta LibrarySuggestions

/-- Bound candidate work when fusing several selector rankings. -/
structure FusionConfig where
  /-- Retrieve a wider pool from each constituent before fusing. -/
  poolFactor : Nat := 2
  maxPool : Nat := 256
  /-- Reciprocal-rank offset. Larger offsets favor agreement over a high single rank. -/
  rankOffset : Nat := 16

/-- Reciprocal-rank fusion of standard Lean selectors. Constituent scores need
not be calibrated. Availability and the caller filter are checked before fusion;
duplicates within one constituent contribute only once. -/
def fuse (selectors : Array Selector) (options : FusionConfig := {}) : Selector :=
    fun goal cfg => do
  if cfg.maxSuggestions == 0 || selectors.isEmpty then return #[]
  if options.poolFactor == 0 || options.maxPool == 0 then
    throwError "JevSelector: fusion pool bounds must be positive"
  let pool := min options.maxPool (cfg.maxSuggestions * options.poolFactor)
  let mut combined : Std.HashMap Name Float := {}
  let env ← getEnv
  for selector in selectors do
    let saved ← saveState
    let candidates ← try
      selector goal { cfg with maxSuggestions := pool }
    finally saved.restore
    let mut seen : Std.HashSet Name := {}
    let mut rank := 0
    for s in candidates.take pool do
      if seen.contains s.name || !env.contains s.name || isDeniedPremise env s.name ||
          !(← cfg.filter s.name) then continue
      seen := seen.insert s.name
      rank := rank + 1
      let contribution := 1 / (options.rankOffset + rank).toFloat
      combined := combined.insert s.name (combined.getD s.name 0 + contribution)
  let sorted := combined.toArray.qsort fun a b =>
    if a.2 == b.2 then a.1.toString < b.1.toString else a.2 > b.2
  return (sorted.take cfg.maxSuggestions).map fun (name, score) =>
    { name, score := score / (score + 1) }

/-- Experimental target-focused retrieval. No extra fit is needed: all weights
and length statistics are computed from the existing eligible statement rows. -/
def Index.targetSelector (idx : Index) : Selector :=
  idx.selector { targetWeight := 4, lengthNormalization := .pivoted }

/-- Experimental fusion preserves the original sparse signal while adding a
target-focused ranking. Importing this module does not install a default selector. -/
def Index.ensembleSelector (idx : Index) (options : FusionConfig := {}) : Selector :=
  fuse #[idx.selector {}, idx.targetSelector] options

end JevSelector
