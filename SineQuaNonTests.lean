import JevSelector.SineQuaNon
import SelectorFixture

open Lean Meta Elab Command JevSelector

set_option maxHeartbeats 2000000

theorem sineLocal (n : Nat) : n = n := rfl
private theorem sinePrivate (n : Nat) : n = n := rfl

run_cmd liftTermElabM do
  SineQuaNon.warmup
  let goal ← mkFreshExprMVar (← inferType (mkConst ``SelectorFixture.keep))
  let imported := SineQuaNon.selector { includeCurrentFile := false }
  let all ← imported goal.mvarId! { maxSuggestions := 64 }
  unless all.size > 1 do throwError "fixture did not exercise imported retrieval"
  unless all.size == (Std.HashSet.ofArray (all.map (·.name))).size do
    throwError "duplicate imported premises"
  -- Ask for only a later-ranked candidate: filtering must refill before truncation.
  let wanted := (all.map (·.name))[all.size - 1]!
  let filtered ← imported goal.mvarId! {
    maxSuggestions := 1, filter := fun name => pure (name == wanted) }
  unless filtered.map (·.name) == #[wanted] do
    throwError "caller filtering did not refill the candidate prefix"
  let none ← imported goal.mvarId! { filter := fun _ => pure false }
  unless none.isEmpty do throwError "caller filter ignored"
  let zero ← imported goal.mvarId! {
    maxSuggestions := 0, filter := fun _ => throwError "filter ran for zero limit" }
  unless zero.isEmpty do throwError "zero limit ignored"
  let capped ← SineQuaNon.selector { includeCurrentFile := false, maxCandidates := 1 }
    goal.mvarId! { maxSuggestions := 100 }
  unless capped.size <= 1 do throwError "candidate cap ignored"
  for name in #[``sineLocal, ``sinePrivate] do
    let result ← SineQuaNon.selector {} goal.mvarId! {
      maxSuggestions := 1, filter := fun n => pure (n == name) }
    unless result.map (·.name) == #[name] do throwError "missing current-file theorem"
    let result ← imported goal.mvarId! { filter := fun n => pure (n == name) }
    unless result.isEmpty do throwError "current-file supplement could not be disabled"
  let future ← SineQuaNon.selector {} goal.mvarId! {
    filter := fun n => pure (n == `sineFuture) }
  unless future.isEmpty do throwError "unavailable future theorem leaked"
  for depth in #[0.5, 0.0 / 0.0, 1.0 / 0.0] do
    let failed ← try
      discard <| SineQuaNon.selector { depthFactor := depth } goal.mvarId! {}
      pure false
    catch _ => pure true
    unless failed do throwError "invalid depth factor accepted"

theorem sineFuture : True := trivial
