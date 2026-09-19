module
public meta import JevSelector.Ensemble
public meta import Lean.Elab.Command
public meta section
namespace JevSelector
open Lean Meta LibrarySuggestions Elab Command

structure DependencyExample where
  owner : String
  dependencies : Array String
  deriving FromJson, ToJson

structure DependencyPremise where
  name : String
  typeHash : Nat
  weight : Float
  deriving FromJson, ToJson

structure DependencyArtifact where
  schema : Nat
  leanVersion : String
  statementArtifactId : String
  examples : Array DependencyExample
  premises : Array DependencyPremise
  provenance : Json
  deriving FromJson, ToJson

structure DependencyIndex where
  statements : Index
  artifact : DependencyArtifact
  examples : Std.HashMap Name (Array Name)
  premises : Std.HashMap Name DependencyPremise

/-- A dependency model is tied to the exact eligible example set of its
statement index. Excluded owners can never reappear as training examples. -/
def loadDependencies (idx : Index) (path : System.FilePath) : IO DependencyIndex := do
  let artifact : DependencyArtifact ← IO.ofExcept
    (Json.parse (← IO.FS.readFile path) >>= fromJson?)
  let identity ← IO.ofExcept (idx.artifact.provenance.getObjValAs? String "artifactId")
  unless artifact.schema == 1 && artifact.leanVersion == Lean.versionString &&
      artifact.statementArtifactId == identity do
    throw <| IO.userError "JevSelector: incompatible dependency artifact or statement index"
  let mut premises := {}
  for p in artifact.premises do
    let name := p.name.toName
    if premises.contains name || !(p.weight > 0 && p.weight < 1000000) then
      throw <| IO.userError "JevSelector: duplicate dependency premise or invalid weight"
    premises := premises.insert name p
  let mut examples : Std.HashMap Name (Array Name) := {}
  for row in artifact.examples do
    let owner := row.owner.toName
    if examples.contains owner || !idx.eligibleNames.contains row.owner then
      throw <| IO.userError s!"JevSelector: duplicate or ineligible proof example {row.owner}"
    let mut seen : Std.HashSet Name := {}
    for text in row.dependencies do
      let name := text.toName
      if seen.contains name || !premises.contains name then
        throw <| IO.userError "JevSelector: duplicate or uncataloged dependency label"
      seen := seen.insert name
    examples := examples.insert owner (row.dependencies.map String.toName)
  unless examples.size == idx.eligibleNames.size do
    throw <| IO.userError "JevSelector: incomplete eligible proof example set"
  return { statements := idx, artifact, examples, premises }

def DependencyIndex.validateEnvironment (idx : DependencyIndex) : MetaM Unit := do
  idx.statements.validateEnvironment
  let env ← getEnv
  for (name, p) in idx.premises do
    if env.constants.map₂.contains name then continue
    if let some info := env.find? name then
      unless (hash info.type).toNat == p.typeHash do
        throwError "JevSelector: incompatible dependency premise {name}; prepare again"

def DependencyIndex.validateHoldouts (idx : DependencyIndex) (owners : Array Name) : IO Json := do
  let statementProvenance ← idx.statements.validateHoldouts owners
  return Json.mkObj [("statements", statementProvenance),
    ("dependencies", idx.artifact.provenance)]

structure DependencyQueryConfig where
  neighbors : Nat := 32
  maxPostingsPerSymbol : Nat := 20000

/-- CPU nearest-neighbor transfer from eligible proof examples. Training examples
need not be imported, but every returned premise is available and caller-approved.
No proof bodies are read at query time. -/
def DependencyIndex.selector (idx : DependencyIndex)
    (options : DependencyQueryConfig := {}) : Selector := fun goal cfg => do
  if cfg.maxSuggestions == 0 || options.neighbors == 0 then return #[]
  let neighbors ← idx.statements.trainingNeighbors goal options.neighbors
    { maxPostingsPerSymbol := options.maxPostingsPerSymbol }
  let mut scores : Std.HashMap Name Float := {}
  for (owner, rank) in neighbors.zipIdx do
    let deps := idx.examples.getD owner #[]
    let vote := 1 / (rank + 1).toFloat / Float.sqrt (max 1 deps.size).toFloat
    for name in deps do
      scores := scores.insert name (scores.getD name 0 + vote)
  let mut ranked : Array (Name × Float) := #[]
  for (name, vote) in scores do
    if let some p := idx.premises[name]? then
      ranked := ranked.push (name, vote * p.weight)
  ranked := ranked.qsort fun a b =>
    if a.2 == b.2 then a.1.toString < b.1.toString else a.2 > b.2
  let env ← getEnv
  let mut result := #[]
  for (name, score) in ranked do
    if result.size >= cfg.maxSuggestions then break
    let some info := env.find? name | continue
    if isDeniedPremise env name || !(← cfg.filter name) then continue
    let some p := idx.premises[name]? | continue
    unless env.constants.map₂.contains name || (hash info.type).toNat == p.typeHash do
      throwError "JevSelector: changed dependency premise {name}; prepare again"
    result := result.push { name, score := score / (score + 1) }
  return result

def DependencyIndex.hybridSelector (idx : DependencyIndex)
    (options : DependencyQueryConfig := {}) : Selector :=
  fuse #[idx.statements.selector {}, idx.selector options] {}

structure DependencyExportConfig where
  index : String
  output : String
  deriving FromJson

/-- Reads only eligible owners' proof VALUES. It never opens referenced helper
bodies, and exports direct public-theorem references rather than transitive edges. -/
elab "#jevselector_dependencies" : command => do
  let some config ← IO.getEnv "JEVSELECTOR_DEPENDENCY_CONFIG"
    | throwError "set JEVSELECTOR_DEPENDENCY_CONFIG"
  let cfg : DependencyExportConfig ← IO.ofExcept
    (Json.parse (← IO.FS.readFile config) >>= fromJson?)
  let idx ← load cfg.index
  liftTermElabM do idx.validateEnvironment
  let identity ← ofExcept (idx.artifact.provenance.getObjValAs? String "artifactId")
  let output ← IO.FS.Handle.mk cfg.output .write
  output.putStrLn <| (Json.mkObj [("kind", toJson "dependency-header"),
    ("leanVersion", toJson Lean.versionString),
    ("statementArtifactId", toJson identity)]).compress
  let env ← getEnv
  for (owner, i) in idx.artifact.eligible.zipIdx do
    let some info := env.find? owner.toName
      | throwError "JevSelector: eligible example {owner} is not imported"
    -- Eligibility is established before obtaining or traversing a proof body.
    let some proof := info.value? (allowOpaque := true)
      | throwError "JevSelector: proof body unavailable for {owner}; import all training modules"
    if proof.hasSorry || proof.hasExprMVar || proof.hasFVar then
      throwError "JevSelector: incomplete eligible proof {owner}; exclude it before preparation"
    let mut dependencies := #[]
    for name in symbols proof do
      if name == owner.toName || !wasOriginallyTheorem env name || isDeniedPremise env name then
        continue
      let some premise := env.find? name | continue
      dependencies := dependencies.push <| Json.mkObj [("name", toJson name.toString),
        ("typeHash", toJson (hash premise.type).toNat)]
    output.putStrLn <| (Json.mkObj [("kind", toJson "proof"), ("owner", toJson owner),
      ("dependencies", .arr dependencies)]).compress
    if i % 10000 == 0 then IO.eprintln s!"JevSelector dependencies: {i}/{idx.artifact.eligible.size}"
  output.flush

end JevSelector
