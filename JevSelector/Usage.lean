module
public meta import JevSelector.Index
public meta section
namespace JevSelector
open Lean Meta LibrarySuggestions

structure UsageFeature where
  symbol : Nat
  weight : Float
  deriving Inhabited, FromJson, ToJson

structure UsagePremise where
  name : String
  typeHash : Nat
  logPrior : Float
  logNormalizer : Float
  features : Array UsageFeature
  deriving Inhabited, FromJson, ToJson

structure UsageArtifact where
  schema : Nat
  leanVersion : String
  statementArtifactId : String
  exampleOwners : Array String
  smoothingMass : Float
  maxFeatures : Nat
  symbols : Array String
  premises : Array UsagePremise
  provenance : Json
  deriving FromJson, ToJson

structure UsageIndex where
  statements : Index
  artifact : UsageArtifact
  knownFeatures : Std.HashSet String
  postings : Std.HashMap String (Array (Nat × Float))

/-- Load the sparse usage model only against its exact eligible statement index. -/
def loadUsage (idx : Index) (path : System.FilePath) : IO UsageIndex := do
  let artifact : UsageArtifact ← IO.ofExcept
    (Json.parse (← IO.FS.readFile path) >>= fromJson?)
  let identity ← IO.ofExcept (idx.artifact.provenance.getObjValAs? String "artifactId")
  unless artifact.schema == 1 && artifact.leanVersion == Lean.versionString &&
      artifact.statementArtifactId == identity &&
      artifact.smoothingMass > 0 && artifact.smoothingMass < 1000000 do
    throw <| IO.userError "JevSelector: incompatible usage artifact or statement index"
  let mut owners : Std.HashSet String := {}
  for owner in artifact.exampleOwners do
    if owners.contains owner || !idx.eligibleNames.contains owner then
      throw <| IO.userError "JevSelector: duplicate or ineligible usage example"
    owners := owners.insert owner
  unless owners.size == idx.eligibleNames.size do
    throw <| IO.userError "JevSelector: incomplete eligible usage example set"
  let mut knownFeatures : Std.HashSet String := {}
  for text in artifact.symbols do
    if knownFeatures.contains text then
      throw <| IO.userError "JevSelector: duplicate usage feature"
    knownFeatures := knownFeatures.insert text
  let mut names : Std.HashSet Name := {}
  let mut lists : Std.HashMap String (List (Nat × Float)) := {}
  for (p, i) in artifact.premises.zipIdx do
    let name := p.name.toName
    unless !names.contains name && p.logPrior > -1000000 && p.logPrior <= 0 &&
        p.logNormalizer >= 0 && p.logNormalizer < 1000000 do
      throw <| IO.userError "JevSelector: duplicate premise or invalid usage score"
    names := names.insert name
    if artifact.maxFeatures != 0 && p.features.size > artifact.maxFeatures then
      throw <| IO.userError "JevSelector: usage feature limit exceeded"
    let mut seen : Std.HashSet Nat := {}
    for feature in p.features do
      unless feature.symbol < artifact.symbols.size && !seen.contains feature.symbol &&
          feature.weight > 0 && feature.weight < 1000000 do
        throw <| IO.userError "JevSelector: invalid or duplicate usage feature weight"
      seen := seen.insert feature.symbol
      let symbol := artifact.symbols[feature.symbol]!
      lists := lists.insert symbol ((i, feature.weight) :: lists.getD symbol [])
  let mut postings := {}
  for (symbol, entries) in lists do
    postings := postings.insert symbol entries.reverse.toArray
  return { statements := idx, artifact, knownFeatures, postings }

def UsageIndex.validateEnvironment (idx : UsageIndex) : MetaM Unit := do
  idx.statements.validateEnvironment
  let env ← getEnv
  for p in idx.artifact.premises do
    let name := p.name.toName
    if env.constants.map₂.contains name then continue
    if let some info := env.find? name then
      unless (hash info.type).toNat == p.typeHash do
        throwError "JevSelector: incompatible usage premise {name}; prepare again"

def UsageIndex.validateHoldouts (idx : UsageIndex) (owners : Array Name) : IO Json := do
  let statements ← idx.statements.validateHoldouts owners
  return Json.mkObj [("statements", statements), ("usage", idx.artifact.provenance)]

structure UsageQueryConfig where
  /-- Deterministic bound per symbol; zero means exhaustive postings. -/
  maxPostingsPerSymbol : Nat := 20000

private def usageQuery (goal : MVarId) : MetaM (Array String) := goal.withContext do
  let mut found : Std.HashSet String := .ofArray
    ((symbols (← instantiateMVars (← goal.getType))).map Name.toString)
  for decl in ← getLCtx do
    for name in symbols (← instantiateMVars decl.type) do found := found.insert name.toString
    if let some value := decl.value? then
      for name in symbols (← instantiateMVars value) do found := found.insert name.toString
  return found.toArray.qsort (· < ·)

/-- Sparse smoothed premise-usage likelihood. Scores preserve order but are not
calibrated probabilities. Only returned, available premises enter suggestions. -/
def UsageIndex.selector (idx : UsageIndex) (options : UsageQueryConfig := {}) : Selector :=
    fun goal cfg => do
  if cfg.maxSuggestions == 0 then return #[]
  let query := (← usageQuery goal).filter idx.knownFeatures.contains
  if query.isEmpty then return #[]
  let mut scores : Std.HashMap Nat Float := {}
  for feature in query do
    let postings := idx.postings.getD feature #[]
    let count := if options.maxPostingsPerSymbol == 0 then postings.size
      else min postings.size options.maxPostingsPerSymbol
    for j in [:count] do
      let (i, weight) := postings[j * postings.size / count]!
      scores := scores.insert i (scores.getD i 0 + weight)
  let mut ranked : Array (Nat × Float) := #[]
  for (i, correction) in scores do
    let p := idx.artifact.premises[i]!
    ranked := ranked.push (i, p.logPrior - query.size.toFloat * p.logNormalizer + correction)
  ranked := ranked.qsort fun a b =>
    if a.2 == b.2 then idx.artifact.premises[a.1]!.name < idx.artifact.premises[b.1]!.name
    else a.2 > b.2
  let env ← getEnv
  let mut result := #[]
  let mut best : Option Float := none
  for (i, score) in ranked do
    if result.size >= cfg.maxSuggestions then break
    let p := idx.artifact.premises[i]!
    let name := p.name.toName
    let some info := env.find? name | continue
    if isDeniedPremise env name || !(← cfg.filter name) then continue
    unless env.constants.map₂.contains name || (hash info.type).toNat == p.typeHash do
      throwError "JevSelector: changed usage premise {name}; prepare again"
    let top := best.getD score
    best := some top
    result := result.push { name, score := Float.exp (score - top) }
  return result

end JevSelector
