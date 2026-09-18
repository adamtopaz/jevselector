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
  postings : Std.HashMap Name (Array Nat)
  weights : Std.HashMap Name Float
  trainingOwners : Std.HashSet String

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
  let mut lists : Std.HashMap Name (List Nat) := {}
  let mut weights := {}
  let mut seen : Std.HashSet String := {}
  for (e, i) in artifact.declarations.zipIdx do
    if verbose && i % 50000 == 0 then progress s!"indexing statement {i}"
    if seen.contains e.name then throw <| IO.userError "JevSelector: duplicate declaration"
    seen := seen.insert e.name
    for s in e.symbols do
      let s := s.toName
      lists := lists.insert s (i :: lists.getD s [])
  for w in artifact.weights do
    unless w.weight > 0 && w.weight < 1000000 do
      throw <| IO.userError "JevSelector: invalid symbol weight"
    weights := weights.insert w.symbol.toName w.weight
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
  return { artifact, postings, weights, trainingOwners }

/-- Validate all available catalog statements during goal-independent warmup.
Unavailable statements are allowed: an artifact can cover more than a source goal's imports. -/
def Index.validateEnvironment (idx : Index) : MetaM Unit := do
  let env ← getEnv
  for e in idx.artifact.declarations do
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

structure QueryConfig where
  /-- Each symbol contributes at most this many postings, sampled evenly.
Zero means exhaustive postings. This bounds common-symbol work deterministically. -/
  maxPostingsPerSymbol : Nat := 20000
  includeCurrentFile : Bool := true

private def goalSymbols (goal : MVarId) : MetaM (Array Name) := goal.withContext do
  let mut found : Std.HashSet Name := {}
  for s in symbols (← instantiateMVars (← goal.getType)) do found := found.insert s
  for localDecl in ← getLCtx do
    for s in symbols (← instantiateMVars localDecl.type) do found := found.insert s
    if let some value := localDecl.value? then
      for s in symbols (← instantiateMVars value) do found := found.insert s
  return found.toArray.qsort (fun a b => a.toString < b.toString)

/-- Sparse weighted symbol overlap, filtered against the *current* environment
and caller before truncating. Scores are normalized overlap, not calibrated probabilities. -/
def Index.selector (idx : Index) (options : QueryConfig := {}) : Selector := fun goal cfg => do
  if cfg.maxSuggestions == 0 then return #[]
  let query ← goalSymbols goal
  let mut scores : Std.HashMap Nat Float := {}
  for symbol in query do
    let postings := idx.postings.getD symbol #[]
    let count := if options.maxPostingsPerSymbol == 0 then postings.size
      else min postings.size options.maxPostingsPerSymbol
    for j in [:count] do
      let i := postings[j * postings.size / count]!
      scores := scores.insert i (scores.getD i 0 + idx.weights.getD symbol 1)
  let env ← getEnv
  -- Rank using artifact data first. Running MetaM filters on every posting is
  -- unnecessary: scan the ranked list until enough available premises pass.
  let mut candidates : Array (String × Float × Nat) := #[]
  let mut used : Std.HashSet String := {}
  for (i, score) in scores do
    let e := idx.artifact.declarations[i]!
    used := used.insert e.name
    candidates := candidates.push (e.name,
      score / Float.sqrt (max 1 e.symbols.size).toFloat, e.typeHash)
  if options.includeCurrentFile then
    for (name, info) in env.constants.map₂ do
      if used.contains name.toString || !wasOriginallyTheorem env name then continue
      let features := symbols info.type
      let score := query.foldl (fun acc s =>
        if features.contains s then acc + idx.weights.getD s 1 else acc) 0
      candidates := candidates.push (name.toString,
        score / Float.sqrt (max 1 features.size).toFloat, (hash info.type).toNat)
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
