import JevSelector
import SelectorFixture

open Lean Meta Elab Command JevSelector

run_cmd liftTermElabM do
  let some path ← IO.getEnv "JEVSELECTOR_TEST_INDEX"
    | throwError "prepare the fixture and set JEVSELECTOR_TEST_INDEX (see tests/run.sh)"
  let idx ← load path
  idx.validateEnvironment
  discard <| idx.validateHoldouts #[`SelectorFixture.held]
  let rejects ← try
    discard <| idx.validateHoldouts #[`SelectorFixture.keep]
    pure false
  catch _ => pure true
  unless rejects do throwError "full-data overlap was accepted"
  let g ← mkFreshExprMVar (← inferType (mkConst ``SelectorFixture.held))
  let result ← idx.selector {} g.mvarId! {
    maxSuggestions := 10
    filter := fun n => pure (n == `SelectorFixture.held) }
  unless result.map (·.name) == #[`SelectorFixture.held] do
    throwError "held-out statement should remain retrievable and the caller filter must hold"
  let lowerRanked ← idx.selector {} g.mvarId! {
    maxSuggestions := 1
    filter := fun n => pure (n == `SelectorFixture.later) }
  unless lowerRanked.map (·.name) == #[`SelectorFixture.later] do
    throwError "selector truncated before applying the caller filter"
  let none ← idx.selector {} g.mvarId! { maxSuggestions := 0 }
  unless none.isEmpty do throwError "zero maximum ignored"
  let futureEntries := idx.artifact.declarations.map fun e => { e with name := "Unavailable.future" }
  let future := { idx with artifact := { idx.artifact with declarations := futureEntries } }
  let result ← future.selector { includeCurrentFile := false } g.mvarId! {}
  unless result.isEmpty do throwError "unavailable future premise leaked"
  let staleEntries := idx.artifact.declarations.map fun e => { e with typeHash := e.typeHash + 1 }
  let stale := { idx with artifact := { idx.artifact with declarations := staleEntries } }
  let rejected ← try
    discard <| stale.selector {} g.mvarId! {}
    pure false
  catch _ => pure true
  unless rejected do throwError "changed theorem statement was accepted"
  let rejectedWarmup ← try
    stale.validateEnvironment
    pure false
  catch _ => pure true
  unless rejectedWarmup do throwError "warmup accepted an incompatible imported statement"
  -- Hygienic internal feature names are opaque text, not parseable identifiers.
  let first := "First._@.Example.1._hygCtx._hyg.8"
  let second := "Second._@.Example.1._hygCtx._hyg.8"
  unless first.toName == second.toName do throwError "regression fixture no longer collides"
  let extraWeights : Array Weight := #[{ symbol := first, weight := 2 },
    { symbol := second, weight := 3 }]
  let opaqueArtifact := { idx.artifact with
    declarations := idx.artifact.declarations.map fun (e : Entry) =>
      { e with symbols := e.symbols ++ #[first, second] }
    weights := idx.artifact.weights ++ extraWeights }
  let opaquePath := path ++ ".feature-names"
  IO.FS.writeFile opaquePath (toJson opaqueArtifact).compress
  let restored ← load opaquePath
  IO.FS.removeFile opaquePath
  unless restored.weights.getD first 0 == 2 && restored.weights.getD second 0 == 3 &&
      restored.postings.contains first && restored.postings.contains second do
    throwError "serialized feature names were collapsed by identifier parsing"


theorem freshlyDeclared (n : Nat) : n = n := rfl

run_cmd liftTermElabM do
  let some path ← IO.getEnv "JEVSELECTOR_TEST_INDEX" | throwError "missing test artifact"
  let idx ← load path
  let goal ← mkFreshExprMVar (← inferType (mkConst ``freshlyDeclared))
  let result ← idx.selector {} goal.mvarId! { filter := fun n => pure (n == ``freshlyDeclared) }
  unless result.map (·.name) == #[``freshlyDeclared] do
    throwError "current-file supplementation failed"
  -- A prepared catalog can contain an older elaboration of this same file.
  -- Its hash and symbols must not override the actual declaration's features.
  let old : Entry := {
    name := "freshlyDeclared"
    moduleName := "JevSelectorTests"
    typeHash := 0
    symbols := #["False"] }
  let i := idx.artifact.declarations.size
  let stale := { idx with
    artifact := { idx.artifact with declarations := idx.artifact.declarations.push old }
    postings := idx.postings.insert "False" #[i] }
  stale.validateEnvironment
  let fresh ← stale.selector {} goal.mvarId! { filter := fun n => pure (n == ``freshlyDeclared) }
  let [suggestion] := fresh.toList | throwError "expected exactly one current-file premise"
  unless suggestion.name == ``freshlyDeclared && suggestion.score > (0 : Float) do
    throwError "cataloged current-file premise did not use live statement features"
  let falseGoal ← mkFreshExprMVar (mkConst ``False)
  let withoutCurrent ← stale.selector { includeCurrentFile := false } falseGoal.mvarId!
    { filter := fun n => pure (n == ``freshlyDeclared) }
  unless withoutCurrent.isEmpty do
    throwError "disabling current-file premises retained a cataloged current-file declaration"
