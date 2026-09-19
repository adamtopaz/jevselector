import JevSelector.ProofDependencies
import SelectorFixture

open Lean Meta Elab Command JevSelector LibrarySuggestions

run_cmd liftTermElabM do
  let some indexPath ← IO.getEnv "JEVSELECTOR_TEST_INDEX" | throwError "missing test index"
  let some modelPath ← IO.getEnv "JEVSELECTOR_TEST_DEPENDENCIES" | throwError "missing test model"
  let idx ← load indexPath
  let model ← loadDependencies idx modelPath
  model.validateEnvironment
  discard <| model.validateHoldouts #[`SelectorFixture.held]
  unless !model.examples.contains `SelectorFixture.held &&
      !model.examples.contains `SelectorFixture.held.helper &&
      !model.premises.contains `Nat.zero_add do
    throwError "excluded proof information entered dependency training"
  unless (model.examples.getD `SelectorFixture.usesPrivate #[]).isEmpty do
    throwError "dependency extraction traversed a private helper proof"
  let goal ← mkFreshExprMVar (← inferType (mkConst ``SelectorFixture.held))
  let neighbors ← idx.trainingNeighbors goal.mvarId! 100
  if neighbors.contains `SelectorFixture.held || neighbors.contains `SelectorFixture.held.helper then
    throwError "held-out statements became proof-neighbor examples"
  let selected ← model.selector {} goal.mvarId! {
    maxSuggestions := 1, filter := fun n => pure (n == ``Nat.add_zero) }
  unless selected.map (·.name) == #[``Nat.add_zero] do
    throwError "proof transfer did not find the eligible theorem's dependency"
  let noSuggestions ← model.selector {} goal.mvarId! { maxSuggestions := 0 }
  unless noSuggestions.isEmpty do throwError "zero limit ignored"
  let mut absent := model
  absent := { absent with
    examples := .ofArray (absent.examples.toArray.map fun (name, _) =>
      (name, #[`Unavailable.future]))
    premises := ({} : Std.HashMap Name DependencyPremise).insert `Unavailable.future
      { name := "Unavailable.future", typeHash := 0, weight := 1 } }
  unless (← absent.selector {} goal.mvarId! {}).isEmpty do
    throwError "future dependency premise leaked into suggestions"
  let mut stalePremises := model.premises
  for (name, p) in model.premises do
    stalePremises := stalePremises.insert name { p with typeHash := p.typeHash + 1 }
  let stale := { model with premises := stalePremises }
  let rejected ← try
    stale.validateEnvironment
    pure false
  catch _ => pure true
  unless rejected do throwError "changed dependency statement passed warmup"
  -- Test the loader, not only the fitter: a corrupt artifact must not restore
  -- an excluded proof example through its reverse/dependency edge records.
  let leaked : DependencyExample := {
    owner := "SelectorFixture.held", dependencies := #["Nat.add_zero"] }
  let poisoned := { model.artifact with examples := model.artifact.examples.push leaked }
  let path := modelPath ++ ".poisoned"
  IO.FS.writeFile path (toJson poisoned).compress
  let rejected ← try
    discard <| loadDependencies idx path
    pure false
  catch _ => pure true
  IO.FS.removeFile path
  unless rejected do throwError "loader accepted excluded proof example"
