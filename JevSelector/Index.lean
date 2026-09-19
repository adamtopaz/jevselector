module
public meta import JevSelector.Features
public meta section
namespace JevSelector
open Lean Meta LibrarySuggestions

structure Weight where
  symbol : String
  weight : Float
  deriving FromJson, ToJson

structure Artifact where
  schema : Nat
  leanVersion : String
  declarations : Array Entry
  weights : Array Weight
  eligible : Array String
  excluded : Array String
  provenance : Json
  deriving FromJson, ToJson

structure Index where
  artifact : Artifact
  /-- Serialized feature keys are opaque text: hygienic constant names do not
  round-trip through `String.toName`. Query features use the same printer. -/
  postings : Std.HashMap String (Array Nat)
  weights : Std.HashMap String Float
  trainingOwners : Std.HashSet String
  /-- Mean statement feature count; computed while loading, never per query. -/
  meanSymbolCount : Float := 1
  /-- Exact eligible example names, distinct from owner-prefix admission checks. -/
  eligibleNames : Std.HashSet String := {}

/-- Loading is separate from querying so clients can account for cold-start cost. -/
def load (path : System.FilePath) : IO Index := do
  let verbose := (← IO.getEnv "JEVSELECTOR_TRACE_LOAD") == some "1"
  let progress := fun (message : String) => if verbose then IO.eprintln s!"JevSelector: {message}" else pure ()
  let json ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
  progress "parsed artifact JSON"
  let artifact : Artifact ← IO.ofExcept (fromJson? json)
  progress s!"decoded {artifact.declarations.size} statements"
  unless artifact.schema == 1 && artifact.leanVersion == Lean.versionString do
    throw <| IO.userError "JevSelector: incompatible artifact schema or Lean version"
  -- Prepend to lists while building: repeatedly appending to shared arrays
  -- would copy very common-symbol postings quadratically.
  let mut lists : Std.HashMap String (List Nat) := {}
  let mut weights := {}
  let mut seen : Std.HashSet String := {}
  for (e, i) in artifact.declarations.zipIdx do
    if verbose && i % 50000 == 0 then progress s!"indexing statement {i}"
    if seen.contains e.name then throw <| IO.userError "JevSelector: duplicate declaration"
    seen := seen.insert e.name
    for s in e.symbols do
      lists := lists.insert s (i :: lists.getD s [])
  for w in artifact.weights do
    unless w.weight > 0 && w.weight < 1000000 do
      throw <| IO.userError "JevSelector: invalid symbol weight"
    weights := weights.insert w.symbol w.weight
  let excluded : Std.HashSet String := .ofArray artifact.excluded
  let mut trainingOwners : Std.HashSet String := {}
  for name in artifact.eligible do
    let mut ownerPrefix := ""
    for part in name.splitOn "." do
      ownerPrefix := if ownerPrefix.isEmpty then part else ownerPrefix ++ "." ++ part
      trainingOwners := trainingOwners.insert ownerPrefix
    unless seen.contains name && !excluded.contains name do
      throw <| IO.userError "JevSelector: invalid training eligibility"
  let eligible : Std.HashSet String := .ofArray artifact.eligible
  for name in seen do
    unless eligible.contains name || excluded.contains name do
      throw <| IO.userError "JevSelector: catalog entry lacks training eligibility"
  progress "validated training eligibility"
  let mut postings := {}
  for (symbol, reversed) in lists do
    postings := postings.insert symbol reversed.reverse.toArray
  progress "postings ready"
  let totalSymbols := artifact.declarations.foldl (fun n e =>
    if eligible.contains e.name then n + e.symbols.size else n) (0 : Nat)
  let meanSymbolCount := max 1 (totalSymbols.toFloat / (max 1 eligible.size).toFloat)
  return { artifact, postings, weights, trainingOwners, meanSymbolCount, eligibleNames := eligible }

/-- Validate imported catalog statements during goal-independent warmup.
Unavailable statements are allowed: an artifact can cover more than a source goal's imports.
Current-file declarations use live features instead: fresh elaboration can change
auxiliary names or instance terms, and the file may have been edited since preparation. -/
def Index.validateEnvironment (idx : Index) : MetaM Unit := do
  let env ← getEnv
  for e in idx.artifact.declarations do
    if env.constants.map₂.contains e.name.toName then continue
    if let some info := env.find? e.name.toName then
      unless (hash info.type).toNat == e.typeHash do
        throwError "JevSelector: incompatible statement {e.name}; prepare again"

/-- Reject evaluation on declarations contributing to fitted statistics.
Absent declarations were outside preparation; they need no exclusion. -/
def Index.validateHoldouts (idx : Index) (owners : Array Name) : IO Json := do
  for owner in owners do
    if idx.trainingOwners.contains owner.toString then
      throw <| IO.userError s!"JevSelector: evaluation overlaps training: {owner}"
  return idx.artifact.provenance

/-- Alternative normalizations are experimental; the default preserves schema-1 ranking. -/
inductive LengthNormalization where
  | squareRoot
  | pivoted
  deriving BEq, Inhabited, Repr

structure QueryConfig where
  /-- Each symbol contributes at most this many postings, sampled evenly.
Zero means exhaustive postings. This bounds common-symbol work deterministically. -/
  maxPostingsPerSymbol : Nat := 20000
  /-- Recompute current-file theorem features from the live environment, including
  declarations already present in the prepared catalog. -/
  includeCurrentFile : Bool := true
  /-- Relative weight of constants in the target. A repeated constant uses the
  largest source weight, so adding duplicate hypotheses does not change retrieval. -/
  targetWeight : Float := 1
  /-- Weight of constants in hypothesis types and local definition values. -/
  contextWeight : Float := 1
  lengthNormalization : LengthNormalization := .squareRoot

private def goalSymbols (goal : MVarId) (options : QueryConfig) :
    MetaM (Array (String × Float)) := goal.withContext do
  let mut found : Std.HashMap String Float := {}
  for s in symbols (← instantiateMVars (← goal.getType)) do
    found := found.insert s.toString options.targetWeight
  for localDecl in ← getLCtx do
    for s in symbols (← instantiateMVars localDecl.type) do
      found := found.insert s.toString (max (found.getD s.toString 0) options.contextWeight)
    if let some value := localDecl.value? then
      for s in symbols (← instantiateMVars value) do
        found := found.insert s.toString (max (found.getD s.toString 0) options.contextWeight)
  return found.toArray.qsort (fun a b => a.1 < b.1)

private def lengthPenalty (idx : Index) (options : QueryConfig) (size : Nat) : Float :=
  match options.lengthNormalization with
  | .squareRoot => Float.sqrt (max 1 size).toFloat
  | .pivoted => 0.25 + 0.75 * (max 1 size).toFloat / idx.meanSymbolCount

private def queryScores (idx : Index) (goal : MVarId) (options : QueryConfig) :
    MetaM (Array (String × Float) × Std.HashMap Nat Float) := do
  unless options.targetWeight > 0 && options.targetWeight < 1000000 &&
      options.contextWeight > 0 && options.contextWeight < 1000000 do
    throwError "JevSelector: query weights must be finite and positive"
  let query ← goalSymbols goal options
  let mut scores : Std.HashMap Nat Float := {}
  for (symbol, queryWeight) in query do
    let postings := idx.postings.getD symbol #[]
    let count := if options.maxPostingsPerSymbol == 0 then postings.size
      else min postings.size options.maxPostingsPerSymbol
    for j in [:count] do
      let i := postings[j * postings.size / count]!
      scores := scores.insert i (scores.getD i 0 + queryWeight * idx.weights.getD symbol 1)
  return (query, scores)

/-- Retrieve eligible TRAINING EXAMPLES by statement similarity. These names are
not premise suggestions: examples may be unavailable in the current environment.
Consumers must separately filter any predicted premises against that environment. -/
def Index.trainingNeighbors (idx : Index) (goal : MVarId) (count : Nat := 32)
    (options : QueryConfig := {}) : MetaM (Array Name) := do
  if count == 0 then return #[]
  let (_, scores) ← queryScores idx goal options
  let mut candidates : Array (String × Float) := #[]
  for (i, score) in scores do
    let e := idx.artifact.declarations[i]!
    unless idx.eligibleNames.contains e.name do continue
    candidates := candidates.push (e.name, score / lengthPenalty idx options e.symbols.size)
  candidates := candidates.qsort fun a b =>
    if a.2 == b.2 then a.1 < b.1 else a.2 > b.2
  return (candidates.take count).map (·.1.toName)

/-- Sparse weighted symbol overlap, filtered against the *current* environment
and caller before truncating. Scores are normalized overlap, not calibrated probabilities. -/
def Index.selector (idx : Index) (options : QueryConfig := {}) : Selector := fun goal cfg => do
  if cfg.maxSuggestions == 0 then return #[]
  let (query, scores) ← queryScores idx goal options
  let env ← getEnv
  -- Rank using artifact data first. Running MetaM filters on every posting is
  -- unnecessary: scan the ranked list until enough available premises pass.
  let mut candidates : Array (String × Float × Nat) := #[]
  for (i, score) in scores do
    let e := idx.artifact.declarations[i]!
    -- Never use stale catalog features/hashes for declarations elaborated here.
    -- The option below also excludes cataloged current-file premises when false.
    if env.constants.map₂.contains e.name.toName then continue
    candidates := candidates.push (e.name,
      score / lengthPenalty idx options e.symbols.size, e.typeHash)
  if options.includeCurrentFile then
    for (name, info) in env.constants.map₂ do
      if !wasOriginallyTheorem env name then continue
      let features := (symbols info.type).map Name.toString
      let score := query.foldl (fun acc (s, queryWeight) =>
        if features.contains s then acc + queryWeight * idx.weights.getD s 1 else acc) 0
      candidates := candidates.push (name.toString,
        score / lengthPenalty idx options features.size, (hash info.type).toNat)
  candidates := candidates.qsort fun a b =>
    if a.2.1 == b.2.1 then a.1 < b.1 else a.2.1 > b.2.1
  let mut result := #[]
  for (text, score, typeHash) in candidates do
    if result.size >= cfg.maxSuggestions then break
    let name := text.toName
    let some info := env.find? name | continue
    if isDeniedPremise env name || !(← cfg.filter name) then continue
    unless (hash info.type).toNat == typeHash do
      throwError "JevSelector: statement changed for {name}; prepare a new artifact"
    result := result.push { name, score := score / (score + 1) }
  return result

end JevSelector
