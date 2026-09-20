module
public meta import JevSelector.Index
public meta section
namespace JevSelector
open Lean Meta LibrarySuggestions

structure BayesFeature where
  symbol : Nat
  weight : Float
  deriving Inhabited, FromJson, ToJson

structure BayesRecord where
  name : String
  typeHash : Nat
  logPrior : Float
  features : Array BayesFeature
  deriving Inhabited, FromJson, ToJson

structure BayesHeader where
  schema : Nat
  kind : String
  leanVersion : String
  statementArtifactId : String
  exampleOwners : Array String
  signaturePriorOwners : Array String
  signaturePrior : Float
  observedWeight : Float
  missingWeight : Float
  maxFeatures : Nat
  symbols : Array String
  premiseCount : Nat
  featureEdges : Nat
  provenance : Json
  deriving FromJson, ToJson

/-- Only metadata survives loading; per-premise feature records are not retained. -/
structure BayesPremise where
  name : Name
  text : String
  typeHash : Nat
  deriving Inhabited

structure BayesIndex where
  statements : Index
  header : BayesHeader
  premises : Array BayesPremise
  priors : Array Float
  featureIds : Std.HashMap String Nat
  postings : Array (Array (Nat × Float))

/-- Stream a versioned header and one premise record per line into an inverted
index. Validate exact training ownership before reading any learned weights. -/
def loadBayes (idx : Index) (path : System.FilePath) : IO BayesIndex :=
    IO.FS.withFile path .read fun handle => do
  let header : BayesHeader ← IO.ofExcept (Json.parse (← handle.getLine) >>= fromJson?)
  let identity ← IO.ofExcept (idx.artifact.provenance.getObjValAs? String "artifactId")
  unless header.schema == 1 && header.kind == "weighted-sparse-bayes-v1" &&
      header.leanVersion == Lean.versionString && header.statementArtifactId == identity &&
      header.signaturePrior.isFinite && header.signaturePrior >= 0 && header.signaturePrior <= 1000000 &&
      header.observedWeight.isFinite && header.observedWeight > 0 && header.observedWeight <= 1000000 &&
      header.missingWeight.isFinite && header.missingWeight >= -1000000 && header.missingWeight <= 0 do
    throw <| IO.userError "JevSelector: incompatible Bayes header or statement index"
  let mut owners : Std.HashSet String := {}
  for owner in header.exampleOwners do
    if owners.contains owner || !idx.eligibleNames.contains owner then
      throw <| IO.userError "JevSelector: duplicate or ineligible Bayes training owner"
    owners := owners.insert owner
  unless owners.size == idx.eligibleNames.size do
    throw <| IO.userError "JevSelector: incomplete Bayes training owner set"
  let mut selfOwners : Std.HashSet String := {}
  for owner in header.signaturePriorOwners do
    if selfOwners.contains owner || !owners.contains owner || header.signaturePrior == 0 then
      throw <| IO.userError "JevSelector: invalid Bayes signature-prior owner"
    selfOwners := selfOwners.insert owner
  unless header.signaturePrior == 0 || selfOwners.size == owners.size do
    throw <| IO.userError "JevSelector: incomplete Bayes signature-prior owner set"
  let mut featureIds : Std.HashMap String Nat := {}
  for (feature, i) in header.symbols.zipIdx do
    if featureIds.contains feature || !idx.weights.contains feature then
      throw <| IO.userError "JevSelector: duplicate or ineligible Bayes feature"
    featureIds := featureIds.insert feature i
  unless featureIds.size == idx.weights.size do
    throw <| IO.userError "JevSelector: incomplete Bayes feature vocabulary"
  let mut premises := #[]
  let mut priors := #[]
  let mut names : Std.HashSet Name := {}
  let mut lists : Array (List (Nat × Float)) := .replicate header.symbols.size []
  let mut edges := 0
  repeat
    let line ← handle.getLine
    if line.isEmpty then break
    if premises.size >= header.premiseCount then
      throw <| IO.userError "JevSelector: extra Bayes premise record"
    let p : BayesRecord ← IO.ofExcept (Json.parse line >>= fromJson?)
    let name := p.name.toName
    unless !p.name.isEmpty && !names.contains name && p.typeHash < 2^64 &&
        p.logPrior.isFinite && p.logPrior > -2000000 && p.logPrior < 2000000 do
      throw <| IO.userError "JevSelector: duplicate or invalid Bayes premise"
    if header.maxFeatures != 0 && p.features.size > header.maxFeatures then
      throw <| IO.userError "JevSelector: Bayes feature limit exceeded"
    let i := premises.size
    let mut seen : Std.HashSet Nat := {}
    for f in p.features do
      unless f.symbol < lists.size && !seen.contains f.symbol &&
          f.weight.isFinite && f.weight > -2000000 && f.weight < 2000000 do
        throw <| IO.userError "JevSelector: invalid or duplicate Bayes feature weight"
      seen := seen.insert f.symbol
      lists := lists.set! f.symbol ((i, f.weight) :: lists[f.symbol]!)
      edges := edges + 1
    names := names.insert name
    premises := premises.push { name, text := p.name, typeHash := p.typeHash }
    priors := priors.push p.logPrior
  unless premises.size == header.premiseCount && edges == header.featureEdges do
    throw <| IO.userError "JevSelector: truncated or inconsistent Bayes artifact"
  for owner in selfOwners do
    unless names.contains owner.toName do
      throw <| IO.userError "JevSelector: missing Bayes signature-prior label"
  let postings := lists.map fun entries => entries.reverse.toArray
  return { statements := idx, header, premises, priors, featureIds, postings }

def BayesIndex.validateEnvironment (idx : BayesIndex) : MetaM Unit := do
  let env ← getEnv
  for p in idx.premises do
    if (env.getModuleIdxFor? p.name).isNone then continue
    if let some info := env.findConstVal? p.name then
      unless (hash info.type).toNat == p.typeHash do
        throwError "JevSelector: incompatible Bayes premise {p.name}; prepare again"

def BayesIndex.validateHoldouts (idx : BayesIndex) (owners : Array Name) : IO Json := do
  let statements ← idx.statements.validateHoldouts owners
  return Json.mkObj [("statements", statements), ("bayes", idx.header.provenance)]

structure BayesQueryConfig where
  /-- Sample at most this many postings evenly per feature; zero is exhaustive.
This approximation is separate from the artifact's disclosed feature pruning. -/
  maxPostingsPerSymbol : Nat := 20000
  heartbeats : Nat := 10000

/-- Scores omit only the query-wide missing-feature constant. All label priors
remain candidates, even without a matching feature. Features have unit weight;
duplicates do not change the score. Set the posting bound to zero for exact
scoring of the stored (possibly feature-pruned) model. -/
def BayesIndex.rankFeatures (idx : BayesIndex) (features : Array String)
    (options : BayesQueryConfig := {}) : Array (Nat × Float) := Id.run do
  let mut ids : Std.HashSet Nat := {}
  for feature in features do
    if let some i := idx.featureIds[feature]? then ids := ids.insert i
  let mut scores := idx.priors
  for id in ids.toArray.qsort (· < ·) do
    let postings := idx.postings[id]!
    let count := if options.maxPostingsPerSymbol == 0 then postings.size
      else min postings.size options.maxPostingsPerSymbol
    for j in [:count] do
      let (i, weight) := postings[j * postings.size / count]!
      scores := scores.set! i (scores[i]! + weight)
  let ranked := scores.mapIdx fun i score => (i, score)
  return ranked.qsort fun a b =>
    if a.2 == b.2 then idx.premises[a.1]!.text < idx.premises[b.1]!.text else a.2 > b.2

private def bayesQuery (goal : MVarId) : MetaM (Array String) := goal.withContext do
  let mut found : Std.HashSet String := .ofArray
    ((symbols (← instantiateMVars (← goal.getType))).map Name.toString)
  for decl in ← getLCtx do
    if decl.isImplementationDetail then continue
    for name in symbols (← instantiateMVars decl.type) do found := found.insert name.toString
    if let some value := decl.value? then
      for name in symbols (← instantiateMVars value) do found := found.insert name.toString
  return found.toArray

/-- Learned ranking as a read-only selector. Imported stale signatures fail;
changed current-file labels are skipped. Fuse with live statement retrieval to
cover edited or untrained premises. Returned scores encode rank, not probability. -/
def BayesIndex.selector (idx : BayesIndex) (options : BayesQueryConfig := {}) : Selector :=
    fun goal cfg => do
  if cfg.maxSuggestions == 0 then return #[]
  if options.heartbeats == 0 then throwError "JevSelector: Bayes heartbeat bound must be positive"
  let saved ← saveState
  try
    withOptions (·.set `maxHeartbeats options.heartbeats) <|
      withTheReader Core.Context (fun c => { c with maxHeartbeats := options.heartbeats * 1000 }) <|
      withCurrHeartbeats <| goal.withContext do
        let ranked := idx.rankFeatures (← bayesQuery goal) options
        let env ← getEnv
        let mut result : Array Suggestion := #[]
        for (i, _) in ranked do
          if result.size >= cfg.maxSuggestions then break
          let p := idx.premises[i]!
          unless env.contains p.name do continue
          let some info := env.findConstVal? p.name | continue
          if isDeniedSignature env p.name info.type then continue
          unless (hash info.type).toNat == p.typeHash do
            if (env.getModuleIdxFor? p.name).isSome then
              throwError "JevSelector: changed Bayes premise {p.name}; prepare again"
            continue
          let beforeFilter ← saveState
          let allowed ← try cfg.filter p.name finally beforeFilter.restore
          unless allowed do continue
          result := result.push { name := p.name, score := 1 / (result.size + 1).toFloat }
        return result
  finally saved.restore

end JevSelector
