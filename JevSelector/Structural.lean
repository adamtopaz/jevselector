module
public meta import JevSelector.Ensemble
public meta import Lean.Meta.LazyDiscrTree
public meta section
namespace JevSelector
open Lean Meta LibrarySuggestions

/-- A signature-only entry. No declaration value is retained or inspected. -/
structure StructuralPremise where
  name : Name
  typeHash : UInt64

/-- An in-memory index for one imported environment. Construct a new instance
after changing/reloading imports. Current-file signatures are rebuilt at each
query, so the cache never retains declarations from later/rolled-back states.
The mutable import tree belongs to this instance, not an environment extension
or Lean's process-global `exact?` cache. -/
structure StructuralIndex where
  importedModules : Array Name
  tree : IO.Ref (Option (LazyDiscrTree StructuralPremise))

/-- Match-work budget, in Lean's user-facing heartbeat units. Initialization is
an explicit separate operation; this budget covers queries and current-file work. -/
structure StructuralConfig where
  heartbeats : Nat := 10000

/-- Signature-only adaptation of Lean 4.33's `LibrarySuggestions.isDeniedPremise`
(Apache-2.0, Lean FRO). Use the same public deny-list extensions without calling
`Environment.find?`, which forces asynchronously elaborated theorem bodies. -/
private def structuralDenied (env : Environment) (name : Name) (type : Expr) : Bool := Id.run do
  if name == ``sorryAx || name.isInternalDetail || isInstanceReducibleCore env name ||
      Lean.Linter.isDeprecated env name then return true
  if (nameDenyListExt.getState env).any (fun p => name.anyS (· == p)) then return true
  if let some moduleIdx := env.getModuleIdxFor? name then
    if isDeniedModule env (env.header.moduleNames[moduleIdx.toNat]!) then return true
  if let .const head _ := type.getForallBody.getAppFn then
    if (typePrefixDenyListExt.getState env).any (·.isPrefixOf head) then return true
  return false

private def structuralEntry (name : Name) (info : AsyncConstantInfo) :
    MetaM (Array (LazyDiscrTree.InitEntry StructuralPremise)) := do
  let type := info.toConstantVal.type
  if structuralDenied (← getEnv) name type then return #[]
  let premise : StructuralPremise := { name, typeHash := hash type }
  forallTelescope type fun _ conclusion => do
    let e ← LazyDiscrTree.InitEntry.fromExpr conclusion premise
    -- Index both directions for consumers such as rewrite, simp, and grind;
    -- suggestions still contain only the original constant name.
    if e.key == .const ``Iff 2 then
      return #[e, ← e.mkSubEntry 0 premise, ← e.mkSubEntry 1 premise]
    else return #[e]

/-- The same general root exclusions used by Lean's library search. -/
private def structuralDroppedKeys : List (List LazyDiscrTree.Key) :=
  [[.star], [.const ``Eq 3, .star, .star, .star]]

private def structuralCheckMessages (previous : MessageLog) : MetaM Unit := do
  let messages := (← getThe Core.State).messages.toList.drop previous.toList.length
  if let some failure := messages.find? (·.severity == .error) then
    throwError "JevSelector: structural signature indexing failed: {failure.data}"

/-- Initialize from imported public signatures only. This requires no training
proofs, exclusions, serialized artifact, neural encoder, or Mathlib dependency.
Measure initialization separately when warming a benchmark. -/
def StructuralIndex.create : MetaM StructuralIndex := do
  let saved ← saveState
  try
    let messages := (← getThe Core.State).messages
    let env ← getEnv
    let ctx ← readThe Core.Context
    let ngen ← LazyDiscrTree.getChildNgen
    let tree ← LazyDiscrTree.createImportedDiscrTree (LazyDiscrTree.createTreeCtx ctx)
      ngen env structuralEntry (constantsPerTask := 6500)
    let tree ← LazyDiscrTree.dropKeys tree structuralDroppedKeys
    structuralCheckMessages messages
    return { importedModules := env.header.moduleNames, tree := ← IO.mkRef (some tree) }
  finally saved.restore

/-- Create an independent mutable cache starting from the current immutable tree.
Lazy refinement of either instance cannot warm the other. For matched benchmarks,
copy a fixed synthetically warmed base before any evaluation-goal queries. This
shares preparation data; it does not change the imported-environment contract. -/
def StructuralIndex.freshCache (idx : StructuralIndex) : IO StructuralIndex := do
  return { idx with tree := ← IO.mkRef (← idx.tree.get) }

/-- Signature-pattern matching, ranked by the number of non-wildcard matches.
Ties use constant names for deterministic order; scores encode rank, not a fitted
probability. Availability, type hashes, and caller filters are checked before
deduplication/truncation. All speculative Lean state is restored; lazy refinement
of the instance's imported signature tree is retained. -/
def StructuralIndex.selector (idx : StructuralIndex) (options : StructuralConfig := {}) :
    Selector := fun goal cfg => do
  if cfg.maxSuggestions == 0 then return #[]
  if options.heartbeats == 0 then throwError "JevSelector: structural heartbeat bound must be positive"
  let saved ← saveState
  try
    let env ← getEnv
    unless env.header.moduleNames == idx.importedModules do
      throwError "JevSelector: structural imports changed; create a new index"
    withOptions (·.set `maxHeartbeats options.heartbeats) <|
      withTheReader Core.Context (fun c => { c with maxHeartbeats := options.heartbeats * 1000 }) <|
      withCurrHeartbeats <| goal.withContext do
        let messages := (← getThe Core.State).messages
        let localTree ← LazyDiscrTree.createModuleTreeRef structuralEntry structuralDroppedKeys
        let candidates ← forallTelescope (← goal.getType) fun _ conclusion =>
          LazyDiscrTree.findMatchesExt localTree idx.tree structuralEntry structuralDroppedKeys
            (constantsPerTask := 6500) (adjustResult := fun score premise => (score, premise))
            (ty := conclusion)
        structuralCheckMessages messages
        let candidates := candidates.qsort fun a b =>
          if a.1 == b.1 then a.2.name.toString < b.2.name.toString else a.1 > b.1
        let mut seen : Std.HashSet Name := {}
        let mut result : Array Suggestion := #[]
        for (_, p) in candidates do
          if seen.contains p.name then continue
          let some info := env.findConstVal? p.name | continue
          if structuralDenied env p.name info.type then continue
          unless hash info.type == p.typeHash do
            throwError "JevSelector: changed structural premise {p.name}; create a new index"
          let beforeFilter ← saveState
          let allowed ← try cfg.filter p.name finally beforeFilter.restore
          unless allowed do continue
          seen := seen.insert p.name
          result := result.push { name := p.name, score := 1 / (result.size + 1).toFloat }
          if result.size >= cfg.maxSuggestions then break
        return result
  finally saved.restore

/-- Expand a fixed, outcome-independent query after initialization. Do not warm
on evaluation goals; lazy expansion for their shapes remains within query time. -/
def StructuralIndex.warmup (idx : StructuralIndex) : MetaM Unit := do
  let saved ← saveState
  try
    let goal ← mkFreshExprMVar (mkConst ``True)
    discard <| idx.selector {} goal.mvarId! { maxSuggestions := 1 }
  finally saved.restore

end JevSelector
