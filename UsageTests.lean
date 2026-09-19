import JevSelector.Usage
import SelectorFixture

open Lean Meta Elab Command JevSelector LibrarySuggestions

run_cmd liftTermElabM do
  let some indexPath ← IO.getEnv "JEVSELECTOR_TEST_INDEX" | throwError "missing test index"
  let some modelPath ← IO.getEnv "JEVSELECTOR_TEST_USAGE" | throwError "missing usage model"
  let idx ← load indexPath
  let model ← loadUsage idx modelPath
  model.validateEnvironment
  discard <| model.validateHoldouts #[`SelectorFixture.held]
  if model.artifact.exampleOwners.contains "SelectorFixture.held" ||
      model.artifact.exampleOwners.contains "SelectorFixture.held.helper" then
    throwError "excluded proof entered usage training"
  let goal ← mkFreshExprMVar (← inferType (mkConst ``SelectorFixture.held))
  let before ← goal.mvarId!.getType
  let selected ← model.selector {} goal.mvarId! {
    maxSuggestions := 1, filter := fun n => pure (n == ``Nat.add_zero) }
  unless selected.map (·.name) == #[``Nat.add_zero] do
    throwError "usage selector failed to transfer the eligible label"
  unless before == (← goal.mvarId!.getType) && !(← goal.mvarId!.isAssigned) do
    throwError "usage query changed its goal"
  unless (← model.selector {} goal.mvarId! { maxSuggestions := 0 }).isEmpty do
    throwError "usage selector ignored zero limit"
  unless (← model.selector {} goal.mvarId! { filter := fun _ => pure false }).isEmpty do
    throwError "usage selector ignored its caller filter"
  let unknown ← mkFreshExprMVar (mkConst ``True)
  unless (← model.selector {} unknown.mvarId! {}).isEmpty do
    throwError "usage selector returned popularity-only results for an unknown query"
  let unavailable := { model with artifact := { model.artifact with
    premises := model.artifact.premises.map fun (p : UsagePremise) =>
      { p with name := "Unavailable.future" } } }
  unless (← unavailable.selector {} goal.mvarId! {}).isEmpty do
    throwError "usage selector returned an unavailable premise"
  let stale := { model with artifact := { model.artifact with
    premises := model.artifact.premises.map fun (p : UsagePremise) =>
      { p with typeHash := p.typeHash + 1 } } }
  let rejected ← try
    stale.validateEnvironment
    pure false
  catch _ => pure true
  unless rejected do throwError "usage warmup accepted a changed imported statement"
  let poisoned := { model.artifact with
    exampleOwners := model.artifact.exampleOwners.push "SelectorFixture.held" }
  let path := modelPath ++ ".poisoned"
  IO.FS.writeFile path (toJson poisoned).compress
  let rejected ← try
    discard <| loadUsage idx path
    pure false
  catch _ => pure true
  IO.FS.removeFile path
  unless rejected do throwError "usage loader accepted an excluded proof example"
