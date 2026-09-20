import Lean
import JevSelector.DependencyGraph
import GraphFixture

open Lean Meta Elab Command JevSelector LibrarySuggestions
set_option maxHeartbeats 4000000

-- A deliberately unresolved body is stronger than a normal source theorem:
-- enumerating env.constants or reading a proof value would block forever.
-- The external test driver kills the process on that regression.
run_cmd liftTermElabM do
  let cached ← DependencyGraph.create
  let saved ← saveState
  let name := `GraphAsyncFixture.pending
  let type ← mkEq (mkApp (mkConst ``GraphFixture.marker) (mkNatLit 7)) (mkNatLit 7)
  let pending ← (← getEnv).addConstAsync name .thm (reportExts := false)
  pending.commitSignature { name, levelParams := [], type }
  try
    setEnv pending.mainEnv
    unless (← getEnv).contains name do throwError "async fixture is unavailable"
    unless (← cached.forward ``GraphFixture.marker).contains name do
      throwError "cached graph omitted an available asynchronous signature"
    unless (← cached.backward name).contains ``GraphFixture.marker do
      throwError "cached graph lost asynchronous type dependencies"
    let fresh ← DependencyGraph.create
    unless (← fresh.forward ``GraphFixture.marker).contains name do
      throwError "fresh graph omitted an available asynchronous signature"
  finally
    setEnv pending.asyncEnv
    addDecl <| .thmDecl {
      name, levelParams := [], type, value := ← mkEqRefl (mkNatLit 7) }
    pending.commitCheckEnv (← getEnv)
    saved.restore
