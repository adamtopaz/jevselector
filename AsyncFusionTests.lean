import JevSelector.Ensemble

open Lean Meta Elab Command JevSelector LibrarySuggestions

-- A composed selector must not wait for a theorem body just to check its name.
-- Only its signature is committed until fusion returns. An external test timeout
-- catches regressions that would wait indefinitely on the unfulfilled promise.
run_cmd liftTermElabM do
  let mark : String → MetaM Unit := fun stage => do
    if let some path ← IO.getEnv "JEVSELECTOR_ASYNC_TEST_PROGRESS" then
      IO.FS.writeFile path stage
  mark "entered"
  let saved ← saveState
  let name := `AsyncFusionFixture.pending
  let goal ← mkFreshExprMVar (mkConst ``True)
  let pending ← (← getEnv).addConstAsync name .thm (reportExts := false)
  pending.commitSignature { name, levelParams := [], type := mkConst ``True }
  mark "signature-committed"
  try
    setEnv pending.mainEnv
    let source : Selector := fun _ _ => pure #[{ name, score := 1 }]
    mark "fusion-start"
    let result ← fuse #[source] {} goal.mvarId! { maxSuggestions := 1 }
    mark "fusion-returned"
    unless result.map (·.name) == #[name] do
      throwError "fusion dropped an available asynchronous signature"
    if ← goal.mvarId!.isAssigned then throwError "fusion assigned the caller goal"
  finally
    -- Fulfil the branch before restoring the test's environment. No synthetic
    -- declaration or incomplete promise escapes into subsequent commands.
    mark "completing-body"
    setEnv pending.asyncEnv
    addDecl <| .thmDecl {
      name, levelParams := [], type := mkConst ``True, value := mkConst ``True.intro }
    pending.commitCheckEnv (← getEnv)
    saved.restore
    mark "complete"
