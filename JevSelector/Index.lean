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

/-- Loading is separate from querying so clients can account for cold-start cost. -/
def load (path : System.FilePath) : IO Index := do
  let artifact : Artifact ← IO.ofExcept (Json.parse (← IO.FS.readFile path) >>= fromJson?)
  unless artifact.schema == 1 && artifact.leanVersion == Lean.versionString do
    throw <| IO.userError "JevSelector: incompatible artifact schema or Lean version"
  let mut postings := {}
  let mut weights := {}
  let mut seen : Std.HashSet String := {}
  for (e, i) in artifact.declarations.zipIdx do
    if seen.contains e.name then throw <| IO.userError "JevSelector: duplicate declaration"
    seen := seen.insert e.name
    for s in e.symbols do
      let s := s.toName
      postings := postings.insert s ((postings.getD s #[]).push i)
  for w in artifact.weights do
    unless w.weight > 0 && w.weight < 1000000 do
      throw <| IO.userError "JevSelector: invalid symbol weight"
    weights := weights.insert w.symbol.toName w.weight
  let excluded : Std.HashSet String := .ofArray artifact.excluded
  for name in artifact.eligible do
    unless seen.contains name && !excluded.contains name do
      throw <| IO.userError "JevSelector: invalid training eligibility"
  let eligible : Std.HashSet String := .ofArray artifact.eligible
  for name in seen do
    unless eligible.contains name || excluded.contains name do
      throw <| IO.userError "JevSelector: catalog entry lacks training eligibility"
  return { artifact, postings, weights }

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
  let eligible : Std.HashSet String := .ofArray idx.artifact.eligible
  for owner in owners do
    for name in eligible do
      if name == owner.toString || (owner.toString ++ ".").isPrefixOf name then
        throw <| IO.userError s!"JevSelector: evaluation overlaps training: {owner} ({name})"
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
  let mut candidates : Array (Name × Float) := #[]
  let mut used : Std.HashSet Name := {}
  for (i, score) in scores do
    let e := idx.artifact.declarations[i]!
    let name := e.name.toName
    let some info := env.find? name | continue
    if isDeniedPremise env name || !(← cfg.filter name) then continue
    unless (hash info.type).toNat == e.typeHash do
      throwError "JevSelector: statement changed for {name}; prepare a new artifact"
    used := used.insert name
    candidates := candidates.push (name, score / Float.sqrt (max 1 e.symbols.size).toFloat)
  if options.includeCurrentFile then
    for (name, info) in env.constants.map₂ do
      if used.contains name || isDeniedPremise env name || !wasOriginallyTheorem env name then continue
      unless ← cfg.filter name do continue
      let features := symbols info.type
      let score := query.foldl (fun acc s =>
        if features.contains s then acc + idx.weights.getD s 1 else acc) 0
      candidates := candidates.push (name, score / Float.sqrt (max 1 features.size).toFloat)
  candidates := candidates.qsort fun a b => if a.2 == b.2 then a.1.toString < b.1.toString else a.2 > b.2
  return candidates[:cfg.maxSuggestions].toArray.map fun (name, score) =>
    { name, score := score / (score + 1) }

end JevSelector
