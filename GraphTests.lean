import Lean
import GraphSupport

open Lean Meta Elab Command JevSelector LibrarySuggestions
open GraphTestSupport
deriving instance Inhabited for Suggestion
set_option maxHeartbeats 4000000
set_option Elab.async false

private def testGraph : MetaM DependencyGraph := do
  let some graph ← graphForTests.get | throwError "missing graph fixture"
  return graph

private def testGoal : MetaM MVarId := do
  let lhs := mkApp (mkConst ``GraphFixture.marker) (mkNatLit 0)
  return (← mkFreshExprMVar (← mkEq lhs (mkNatLit 0))).mvarId!

private def chooseDirection (name : Name) (direction : String) : GraphRanker :=
    fun _ _ choices => do
  let indices := (List.range choices.size).toArray
  let selected := indices.filter fun i =>
    choices[i]!.getObjValD "constant" == toJson name.toString &&
      choices[i]!.getObjValD "direction" == toJson direction
  let none := indices.filter fun i => choices[i]!.getObjValD "direction" == .str "none"
  let first := selected ++ none.filter (fun i => !selected.contains i)
  return first ++ indices.filter (fun i => !first.contains i)

run_cmd liftTermElabM do
  let graph ← DependencyGraph.create
  graphForTests.set (some graph)
  graphEarlierEnv.set (some (← getEnv))
  unless graph.entries.contains ``GraphFixture.forwardEdge do
    throwError "graph omitted an imported public signature"
  let backwards ← graph.backward ``GraphFixture.forwardEdge
  unless backwards.contains ``GraphFixture.marker && backwards.contains ``Nat do
    throwError "backward edges do not describe the type"
  let body ← graph.backward ``GraphFixture.bodyOnly
  if body.contains ``GraphFixture.marker then throwError "graph opened a declaration body"
  let forwards ← graph.forward ``GraphFixture.marker
  unless forwards.contains ``GraphFixture.forwardEdge && forwards.contains ``GraphFixture.anotherEdge do
    throwError "forward type dependencies were lost"
  if forwards.contains ``GraphFixture.bodyOnly || forwards.any Name.isInternalDetail then
    throwError "body dependencies or private declarations entered the forward graph"
  unless (← graph.forward `Unavailable.future).isEmpty &&
      (← graph.backward `Unavailable.future).isEmpty do
    throwError "unavailable constants entered graph traversal"
  let incompatible := { graph with importedModules := #[] }
  let rejected ← try
    discard <| incompatible.forward ``GraphFixture.marker
    pure false
  catch _ => pure true
  unless rejected do throwError "graph accepted an incompatible import set"
  let some entry := graph.entries[``GraphFixture.forwardEdge]?
    | throwError "fixture entry missing"
  let changed := { entry with typeHash := entry.typeHash + 1 }
  let stale := { graph with entries := graph.entries.insert ``GraphFixture.forwardEdge changed }
  let rejected ← try
    discard <| stale.forward ``GraphFixture.marker
    pure false
  catch _ => pure true
  unless rejected do throwError "graph accepted an imported signature mismatch"

theorem graphLater : GraphFixture.marker 3 = 3 := rfl

run_cmd liftTermElabM do
  let graph ← testGraph
  unless (← graph.forward ``GraphFixture.marker).contains ``graphLater do
    throwError "graph did not include a new current-file signature"
  let some earlier ← graphEarlierEnv.get | throwError "missing earlier environment"
  withEnv earlier do
    if (← graph.forward ``GraphFixture.marker).contains `graphLater then
      throwError "a rolled-back declaration remained in the graph"
    addDecl <| .axiomDecl {
      name := `graphLater, levelParams := [], type := mkConst ``True, isUnsafe := false }
    if (← graph.forward ``GraphFixture.marker).contains `graphLater then
      throwError "an edited declaration retained stale forward edges"
    unless (← graph.forward ``True).contains `graphLater do
      throwError "an edited declaration did not acquire its new forward edges"

run_cmd liftTermElabM do
  let graph ← testGraph
  let goal ← testGoal
  let rank : GraphRanker := fun question g choices => do
    unless question.contains "Backward" && question.contains "forward" &&
        choices.all (fun c => !((c.getObjValAs? String "type").toOption.getD "").isEmpty) do
      throwError "graph choices lost their mathematical descriptions"
    chooseDirection ``GraphFixture.marker "forward" question g choices
  let result ← graph.guided {} rank LibrarySuggestions.empty goal {
    maxSuggestions := 8, filter := fun name => pure (name == ``GraphFixture.forwardEdge) }
  unless result.map (·.name) == #[``GraphFixture.forwardEdge] do
    throwError "guided forward traversal did not return the permitted premise"
  let limited ← graph.guided { maxVisited := 1, maxEdgesPerNode := 1, maxRounds := 3 }
    rank LibrarySuggestions.empty goal { maxSuggestions := 100 }
  unless limited.size <= 1 do throwError "graph exceeded its visited/edge bound"
  let calls ← IO.mkRef (0 : Nat)
  let baseline : Array Suggestion := #[{ name := ``GraphFixture.forwardEdge, score := 0.42 }]
  let base : Selector := fun _ _ => pure baseline
  for failure in #[false, true] do
    let fallback : GraphRanker := fun _ _ _ => do
      calls.modify (· + 1)
      if failure then throwError "offline ranker failure"
      return #[999]
    let got ← graph.guided {} fallback base goal { maxSuggestions := 1 }
    unless got.map (·.name) == baseline.map (·.name) && got[0]!.score == 0.42 do
      throwError "graph failure did not preserve the base ranking"
  unless (← calls.get) == 2 do throwError "graph call count exceeded one round"
  let noCalls : GraphRanker := fun _ _ _ => throwError "ranker must not be called"
  let got ← graph.guided { maxRounds := 0 } noCalls base goal { maxSuggestions := 1 }
  unless got[0]!.score == 0.42 do throwError "zero graph rounds changed base selection"
  unless (← graph.guided {} noCalls base goal { maxSuggestions := 0 }).isEmpty do
    throwError "graph ignored zero requested suggestions"
  let mutated ← IO.mkRef false
  let mutate : GraphRanker := fun q g choices => do
    g.assign (← mkEqRefl (mkNatLit 0))
    addDecl <| .axiomDecl {
      name := `GraphTestTemporary, levelParams := [], type := mkConst ``True, isUnsafe := false }
    mutated.set true
    chooseDirection ``GraphFixture.marker "forward" q g choices
  discard <| graph.guided {} mutate LibrarySuggestions.empty goal {
    filter := fun _ => do
      if ← goal.isAssigned then throwError "ranker changed the goal"
      goal.assign (← mkEqRefl (mkNatLit 0))
      pure true }
  unless ← mutated.get do throwError "state mutation fixture was not exercised"
  if (← goal.isAssigned) || (← getEnv).contains `GraphTestTemporary then
    throwError "graph query leaked Lean state"

-- Access to the current theorem's signature must not wait for its unfinished
-- proof value. The external test driver also bounds this process's runtime.
theorem graphPending : GraphFixture.marker 4 = 4 := by
  run_tac
    let graph ← testGraph
    let names ← graph.forward ``GraphFixture.marker
    let env ← getEnv
    -- Lean may hide the current theorem until its proof is complete. A
    -- signature-only query must terminate either way and honor availability.
    unless names.contains `graphPending == env.contains `graphPending do
      throwError "graph disagrees with pending theorem availability"
  rfl
