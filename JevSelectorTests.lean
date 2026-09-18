import JevSelector
import SelectorFixture

open Lean Meta Elab Command JevSelector

run_cmd liftTermElabM do
  let some path ← IO.getEnv "JEVSELECTOR_TEST_INDEX"
    | throwError "prepare the fixture and set JEVSELECTOR_TEST_INDEX (see tests/run.sh)"
  let idx ← load path
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
