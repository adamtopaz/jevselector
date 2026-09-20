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
  /-- Rewrite direction preference; conclusion entries have weight one. -/
  weight : Nat := 1

/-- Which parts of a public signature are indexed. Neither mode reads proofs. -/
inductive StructuralMode where
  | conclusion
  | rewrites
  deriving BEq, Inhabited

/-- An in-memory index for one imported environment. Construct a new instance
after changing/reloading imports. Current-file signatures are rebuilt at each
query, so the cache never retains declarations from later/rolled-back states.
The mutable import tree belongs to this instance, not an environment extension
or Lean's process-global `exact?` cache. -/
structure StructuralIndex where
  importedModules : Array Name
  tree : IO.Ref (Option (LazyDiscrTree StructuralPremise))
  mode : StructuralMode := .conclusion

/-- Match-work budget, in Lean's user-facing heartbeat units. Initialization is
an explicit separate operation; this budget covers queries and current-file work. -/
structure StructuralConfig where
  heartbeats : Nat := 10000
  /-- Rewrite-mode traversal bounds; conclusion mode does not traverse subterms. -/
  maxNodes : Nat := 256
  maxQueries : Nat := 64
  maxDepth : Nat := 8
  maxHypotheses : Nat := 8

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

private def structuralEntry (mode : StructuralMode) (name : Name) (info : AsyncConstantInfo) :
    MetaM (Array (LazyDiscrTree.InitEntry StructuralPremise)) := do
  let type := info.toConstantVal.type
  if structuralDenied (← getEnv) name type then return #[]
  let premise : StructuralPremise := { name, typeHash := hash type }
  if mode == .rewrites then
    -- Signature-only adaptation of Lean.Meta.Rewrites.addImport (Lean FRO,
    -- Apache-2.0). Retain the selector deny policy and explicit instance cache.
    return ← withNewMCtxDepth <| withReducible <|
      forallTelescopeReducing type fun _ conclusion => do
        match conclusion.getAppFnArgs with
        | (``Eq, #[_, lhs, rhs]) | (``Iff, #[lhs, rhs]) =>
          return #[← LazyDiscrTree.InitEntry.fromExpr lhs { premise with weight := 2 },
            ← LazyDiscrTree.InitEntry.fromExpr rhs premise]
        | _ => return #[]
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
def StructuralIndex.create (mode : StructuralMode := .conclusion) : MetaM StructuralIndex := do
  let saved ← saveState
  try
    let messages := (← getThe Core.State).messages
    let env ← getEnv
    let ctx ← readThe Core.Context
    let ngen ← LazyDiscrTree.getChildNgen
    let tree ← LazyDiscrTree.createImportedDiscrTree (LazyDiscrTree.createTreeCtx ctx)
      ngen env (structuralEntry mode) (constantsPerTask := 6500)
    let tree ← LazyDiscrTree.dropKeys tree structuralDroppedKeys
    structuralCheckMessages messages
    return { importedModules := env.header.moduleNames, tree := ← IO.mkRef (some tree), mode }
  finally saved.restore

/-- Create an independent mutable cache starting from the current immutable tree.
Lazy refinement of either instance cannot warm the other. For matched benchmarks,
copy a fixed synthetically warmed base before any evaluation-goal queries. This
shares preparation data; it does not change the imported-environment contract. -/
def StructuralIndex.freshCache (idx : StructuralIndex) : IO StructuralIndex := do
  return { idx with tree := ← IO.mkRef (← idx.tree.get) }

private structure RewriteTraversal where
  seen : Std.HashSet Expr := {}
  queries : Nat := 0
  candidates : Array (Nat × StructuralPremise) := #[]

/-- Match while binders are in scope, visiting each expression once and bounding
both syntactic traversal and expensive discrimination-tree queries. -/
private partial def rewriteMatches (lookup : Expr → MetaM (Array (Nat × StructuralPremise)))
    (options : StructuralConfig) (state : IO.Ref RewriteTraversal) (e : Expr)
    (depth : Nat := 0) : MetaM Unit := do
  let s ← state.get
  if depth > options.maxDepth || s.seen.size >= options.maxNodes ||
      s.queries >= options.maxQueries || s.seen.contains e then return
  state.set { s with seen := s.seen.insert e }
  match e with
  | .forallE .. =>
    forallTelescope e fun args body => do
      rewriteMatches lookup options state body (depth + 1)
      for arg in args do
        rewriteMatches lookup options state (← inferType arg) (depth + 1)
  | .lam .. | .letE .. =>
    lambdaLetTelescope e fun args body => do
      rewriteMatches lookup options state body (depth + 1)
      for arg in args do
        rewriteMatches lookup options state (← inferType arg) (depth + 1)
  | .mdata _ body => rewriteMatches lookup options state body depth
  | .app .. | .const .. | .proj .. =>
    unless e.hasLooseBVars do
      let candidates ← lookup e
      state.modify fun s => { s with queries := s.queries + 1, candidates := s.candidates ++ candidates }
    match e with
    | .app .. =>
      for arg in e.getAppArgs do
        rewriteMatches lookup options state arg (depth + 1)
    | .proj _ _ arg => rewriteMatches lookup options state arg (depth + 1)
    | _ => pure ()
  | _ => pure ()

/-- Signature-pattern matching, ranked by the number of non-wildcard matches.
Ties use constant names for deterministic order; scores encode rank, not a fitted
probability. Availability, type hashes, and caller filters are checked before
deduplication/truncation. All speculative Lean state is restored; lazy refinement
of the instance's imported signature tree is retained. -/
def StructuralIndex.selector (idx : StructuralIndex) (options : StructuralConfig := {}) :
    Selector := fun goal cfg => do
  if cfg.maxSuggestions == 0 then return #[]
  if options.heartbeats == 0 then throwError "JevSelector: structural heartbeat bound must be positive"
  if idx.mode == .rewrites && (options.maxNodes == 0 || options.maxQueries == 0 ||
      options.maxDepth == 0) then
    throwError "JevSelector: rewrite traversal bounds must be positive"
  let saved ← saveState
  try
    let env ← getEnv
    unless env.header.moduleNames == idx.importedModules do
      throwError "JevSelector: structural imports changed; create a new index"
    withOptions (·.set `maxHeartbeats options.heartbeats) <|
      withTheReader Core.Context (fun c => { c with maxHeartbeats := options.heartbeats * 1000 }) <|
      withCurrHeartbeats <| goal.withContext do
        let messages := (← getThe Core.State).messages
        let entry := structuralEntry idx.mode
        let localTree ← LazyDiscrTree.createModuleTreeRef entry structuralDroppedKeys
        let lookup := fun expression =>
          LazyDiscrTree.findMatchesExt localTree idx.tree entry structuralDroppedKeys
            (constantsPerTask := 6500)
            (adjustResult := fun score premise => (score * premise.weight, premise))
            (ty := expression)
        let candidates ← if idx.mode == .conclusion then
          forallTelescope (← goal.getType) fun _ conclusion => lookup conclusion
        else do
          let traversal ← IO.mkRef ({} : RewriteTraversal)
          rewriteMatches lookup options traversal (← goal.getType)
          let mut hypotheses := 0
          for localDecl in ← getLCtx do
            if hypotheses >= options.maxHypotheses then break
            if localDecl.isImplementationDetail || !(← isProp localDecl.type) then continue
            hypotheses := hypotheses + 1
            rewriteMatches lookup options traversal localDecl.type
          pure (← traversal.get).candidates
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
