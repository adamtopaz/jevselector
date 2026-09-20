module
public meta import JevSelector.Ensemble
public meta section
namespace JevSelector
open Lean Meta LibrarySuggestions

/-- The injected callback has the same structural type as JevHammer's budgeted
selector ranker. This module does not create a client or import JevHammer. -/
abbrev GraphRanker := String → MVarId → Array Json → MetaM (Array Nat)

/-- Signature metadata only; no declaration value or proof is retained. -/
structure TypeDependencyEntry where
  typeHash : UInt64
  dependencies : Array Name

/-- Imported public signatures and their reverse edges. Recreate after reloading
imports. Current-file entries are deliberately absent from this cached value. -/
structure DependencyGraph where
  importedModules : Array Name
  entries : Std.HashMap Name TypeDependencyEntry
  forwardEdges : Std.HashMap Name (Array Name)

private def dependencyEntry (type : Expr) : TypeDependencyEntry :=
  { typeHash := hash type, dependencies := symbols type }

private def addForwardEdges (forward : Std.HashMap Name (Array Name))
    (name : Name) (entry : TypeDependencyEntry) : Std.HashMap Name (Array Name) :=
  entry.dependencies.foldl (fun edges dependency =>
    edges.insert dependency ((edges.getD dependency #[]).push name)) forward

/-- Index only signatures available from the current imports. This is not fitted
proof information and requires neither training examples nor proof holdouts. -/
def DependencyGraph.create : MetaM DependencyGraph := do
  let env ← getEnv
  let mut entries : Std.HashMap Name TypeDependencyEntry := {}
  let mut forwardEdges : Std.HashMap Name (Array Name) := {}
  -- Accessing env.constants waits for kernel checking, including unfinished
  -- local proof bodies. Imported module names need no such synchronization.
  let names := env.header.moduleData.flatMap (·.constNames) |>.qsort Name.quickLt
  for name in names do
    Core.checkMaxHeartbeats "dependency graph initialization"
    if !env.contains name || entries.contains name then continue
    let some info := env.findConstVal? name (skipRealize := true) | continue
    if isDeniedSignature env name info.type then continue
    let entry := dependencyEntry info.type
    entries := entries.insert name entry
    forwardEdges := addForwardEdges forwardEdges name entry
  return { importedModules := env.header.moduleNames, entries, forwardEdges }

private structure DependencyGraphView where
  graph : DependencyGraph
  current : Std.HashMap Name TypeDependencyEntry
  currentForward : Std.HashMap Name (Array Name)

private def DependencyGraph.view (graph : DependencyGraph) : MetaM DependencyGraphView := do
  let env ← getEnv
  unless env.header.moduleNames == graph.importedModules do
    throwError "JevSelector: dependency graph imports changed; create a new index"
  let mut current : Std.HashMap Name TypeDependencyEntry := {}
  let mut forward : Std.HashMap Name (Array Name) := {}
  let infos := (← env.getLocalConstantInfos (skipTheoremSubDecls := true)).qsort
    (fun a b => Name.quickLt a.name b.name)
  for asyncInfo in infos do
    Core.checkMaxHeartbeats "dependency graph current-file signatures"
    let info := asyncInfo.toConstantVal
    let name := info.name
    if isDeniedSignature env name info.type then continue
    let entry := dependencyEntry info.type
    current := current.insert name entry
    forward := addForwardEdges forward name entry
  return { graph, current, currentForward := forward }

private def DependencyGraphView.live (view : DependencyGraphView) (name : Name) :
    MetaM (Option TypeDependencyEntry) := do
  let env ← getEnv
  let some info := env.findConstVal? name (skipRealize := true) | return none
  if isDeniedSignature env name info.type then return none
  if !env.isImportedConst name then return view.current[name]?
  let some cached := view.graph.entries[name]? | return none
  unless hash info.type == cached.typeHash do
    throwError "JevSelector: imported dependency signature changed; create a new index"
  return some cached

/-- Backward traversal may pass through an available seed that is not itself an
admissible premise, but it still reads only its type. -/
private def DependencyGraphView.backward (view : DependencyGraphView) (name : Name) :
    MetaM (Array Name) := do
  let env ← getEnv
  let some info := env.findConstVal? name | return #[]
  if let some cached ← view.live name then return cached.dependencies.filter env.contains
  return (symbols info.type).filter env.contains

private def DependencyGraphView.forward (view : DependencyGraphView) (name : Name)
    (limit : Nat := 0) : MetaM (Array Name) := do
  let candidates := view.graph.forwardEdges.getD name #[] ++ view.currentForward.getD name #[]
  let mut seen : Std.HashSet Name := {}
  let mut result := #[]
  for candidate in candidates do
    Core.checkMaxHeartbeats "dependency graph forward edges"
    if seen.contains candidate then continue
    let some entry ← view.live candidate | continue
    -- A current-file replacement need not have its imported predecessor's edges.
    unless entry.dependencies.contains name do continue
    seen := seen.insert candidate
    result := result.push candidate
    if limit > 0 && result.size >= limit then break
  return result.qsort Name.quickLt

/-- Available constants mentioned by a constant's type. No bodies are opened. -/
def DependencyGraph.backward (graph : DependencyGraph) (name : Name) : MetaM (Array Name) := do
  (← graph.view).backward name

/-- Available public declarations whose types mention a constant. Filtering
happens before any traversal bound or degree is computed. -/
def DependencyGraph.forward (graph : DependencyGraph) (name : Name) : MetaM (Array Name) := do
  (← graph.view).forward name

structure GraphConfig where
  /-- One batch by default, preserving calls for proof-state search. -/
  maxRounds : Nat := 1
  maxFrontier : Nat := 8
  maxVisited : Nat := 128
  maxEdgesPerNode : Nat := 32
  /-- Bound available forward candidates inspected for each frontier node.
  Filtering precedes this cap; the heartbeat budget also bounds rejected work. -/
  maxForwardCandidates : Nat := 256
  maxTypeChars : Nat := 1200
  heartbeats : Nat := 10000
  rankOffset : Nat := 16

private structure GraphNode where
  name : Name
  backward : Array Name
  forward : Array Name

private def graphSeeds (goal : MVarId) : MetaM (Array Name) := goal.withContext do
  let mut found : Std.HashSet Name := .ofArray (symbols (← instantiateMVars (← goal.getType)))
  for decl in ← getLCtx do
    if decl.isImplementationDetail then continue
    for name in symbols (← instantiateMVars decl.type) do found := found.insert name
    if let some value := decl.value? then
      for name in symbols (← instantiateMVars value) do found := found.insert name
  return found.toArray.qsort Name.quickLt

private def graphQuestion : String :=
  "Is this the most useful direction to explore from this Lean constant to find premises for the goal? Backward means constants mentioned in its type; forward means available declarations whose types mention it. Use the displayed type and the goal's local hypotheses; type_truncated marks shortened signatures and forward_count_capped marks a bounded neighborhood. Prefer no expansion when neither direction is useful. Only one direction will be taken for each constant."

private def graphPermutation (order : Array Nat) (size : Nat) : Bool :=
  order.size == size && (List.range size).all (order.contains ·)

/-- A guided traversal decorates a caller-supplied CPU selector. Bounded graph
expansion contributes a second ranking, fused with the unchanged initial base
ranking. With no expansions, return that base ranking directly. -/
def DependencyGraph.guided (graph : DependencyGraph) (options : GraphConfig := {})
    (rank : GraphRanker) (base : Selector) : Selector := fun goal cfg => do
  if cfg.maxSuggestions == 0 then return #[]
  if options.heartbeats == 0 || options.maxFrontier == 0 || options.maxVisited == 0 ||
      options.maxEdgesPerNode == 0 || options.maxForwardCandidates == 0 ||
      options.maxTypeChars == 0 then
    throwError "JevSelector: graph work bounds must be positive"
  let saved ← saveState
  try
    -- Preserve the base selector's own work bound. Graph heartbeats cover only
    -- the extra signature traversal, ranking payloads and final fusion.
    let baseline ← base goal cfg
    saved.restore
    if options.maxRounds == 0 then return baseline
    withOptions (·.set `maxHeartbeats options.heartbeats) <|
      withTheReader Core.Context (fun c => { c with maxHeartbeats := options.heartbeats * 1000 }) <|
      withCurrHeartbeats <| goal.withContext do
        let view ← graph.view
        let env ← getEnv
        let seeds ← graphSeeds goal
        let seedSet : Std.HashSet Name := .ofArray seeds
        let mut baseRanks : Std.HashMap Name Nat := {}
        for (suggestion, i) in baseline.zipIdx do
          unless baseRanks.contains suggestion.name do baseRanks := baseRanks.insert suggestion.name i
        let mut frontier := seeds
        let mut visited : Std.HashSet Name := {}
        let mut reached : Std.HashMap Name Nat := {}
        for _ in [:options.maxRounds] do
          if frontier.isEmpty || visited.size >= options.maxVisited then break
          let mut nodes : Array GraphNode := #[]
          -- Counts describe a bounded available neighborhood. Unavailable
          -- declarations cannot consume the candidate cap or change its count.
          for name in frontier do
            Core.checkMaxHeartbeats "dependency graph frontier"
            if visited.contains name || !env.contains name then continue
            let backward ← view.backward name
            let forward ← view.forward name options.maxForwardCandidates
            nodes := nodes.push { name, backward, forward }
          nodes := nodes.qsort fun a b =>
            if a.forward.size == b.forward.size then Name.quickLt a.name b.name
            else a.forward.size < b.forward.size
          nodes := nodes.take (min options.maxFrontier (options.maxVisited - visited.size))
          if nodes.isEmpty then break
          let mut choices := #[]
          for node in nodes do
            let some info := env.findConstVal? node.name
              | throwError "JevSelector: dependency graph frontier became unavailable"
            let chars := (← ppExpr info.type).pretty.toList
            let type := String.ofList (chars.take options.maxTypeChars)
            for direction in #["none", "backward", "forward"] do
              choices := choices.push <| Json.mkObj [("constant", toJson node.name.toString),
                ("type", toJson type), ("direction", toJson direction),
                ("type_truncated", toJson (decide (chars.length > options.maxTypeChars))),
                ("backward_count", toJson node.backward.size),
                ("forward_count_capped", toJson (node.forward.size == options.maxForwardCandidates)),
                ("forward_count", toJson node.forward.size)]
          -- The caller may inject a simple mock instead of JevHammer's checked
          -- callback. Preserve read-only behavior and validate either path.
          let beforeRank ← saveState
          let order ← try rank graphQuestion goal choices
            catch _ => pure (List.range choices.size).toArray
            finally beforeRank.restore
          let order := if graphPermutation order choices.size then order
            else (List.range choices.size).toArray
          let mut decisions : Std.HashMap Nat Nat := {}
          for index in order do
            unless decisions.contains (index / 3) do
              decisions := decisions.insert (index / 3) (index % 3)
          let mut next : Std.HashSet Name := {}
          for (node, i) in nodes.zipIdx do
            visited := visited.insert node.name
            let direction := decisions.getD i 0
            let neighbors := if direction == 1 then node.backward else
              if direction == 2 then node.forward else #[]
            let mut scored : Array (Name × Nat) := #[]
            for name in neighbors do
              Core.checkMaxHeartbeats "dependency graph neighbor ranking"
              let some info := env.findConstVal? name | continue
              let overlap := (symbols info.type).foldl (fun n s =>
                n + if seedSet.contains s then 1 else 0) 0
              scored := scored.push (name, overlap)
            scored := scored.qsort fun a b =>
              let ra := baseRanks.getD a.1 baseline.size
              let rb := baseRanks.getD b.1 baseline.size
              if ra != rb then ra < rb else
                if a.2 != b.2 then a.2 > b.2 else Name.quickLt a.1 b.1
            for (name, overlap) in scored.take options.maxEdgesPerNode do
              if reached.size >= options.maxVisited then break
              reached := reached.insert name (reached.getD name 0 + 1 + overlap)
              if !visited.contains name then next := next.insert name
          frontier := next.toArray.qsort Name.quickLt
        if reached.isEmpty then return baseline
        let ranked := reached.toArray.qsort fun a b =>
          if a.2 == b.2 then Name.quickLt a.1 b.1 else a.2 > b.2
        let mut extra : Array Suggestion := #[]
        for (name, _) in ranked do
          let some info := env.findConstVal? name | continue
          if isDeniedSignature env name info.type then continue
          let beforeFilter ← saveState
          let allowed ← try cfg.filter name finally beforeFilter.restore
          unless allowed do continue
          extra := extra.push { name, score := 1 / (extra.size + 1).toFloat }
          if extra.size >= cfg.maxSuggestions then break
        if extra.isEmpty then return baseline
        fuse #[fun _ _ => pure baseline, fun _ _ => pure extra]
          { poolFactor := 1, maxPool := cfg.maxSuggestions, rankOffset := options.rankOffset } goal cfg
  finally saved.restore

end JevSelector
