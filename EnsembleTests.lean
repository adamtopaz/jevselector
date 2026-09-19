import JevSelector.Ensemble
import SelectorFixture

open Lean Meta Elab Command JevSelector LibrarySuggestions

run_cmd liftTermElabM do
  let goal ← mkFreshExprMVar (mkConst ``True)
  let first : Selector := fun _ _ => pure #[
    { name := `SelectorFixture.keep, score := 1.0 }, { name := `SelectorFixture.keep, score := 1.0 },
    { name := `Unavailable.future, score := 1.0 }, { name := `SelectorFixture.held, score := 1.0 }]
  let second : Selector := fun _ _ => pure #[
    { name := `SelectorFixture.held, score := 1.0 }, { name := `SelectorFixture.later, score := 1.0 }]
  let result ← fuse #[first, second] {} goal.mvarId! { maxSuggestions := 3 }
  unless result.map (·.name) ==
      #[`SelectorFixture.held, `SelectorFixture.keep, `SelectorFixture.later] do
    throwError "fusion must reward agreement without rewarding duplicate or unavailable names"
  let filtered ← fuse #[first, second] {} goal.mvarId! {
    maxSuggestions := 1, filter := fun n => pure (n == `SelectorFixture.later) }
  -- Constituents are allowed to ignore the caller filter, but fusion must not.
  unless filtered.map (·.name) == #[`SelectorFixture.later] do
    throwError "fusion violated availability/filter-before-truncation"
  let empty ← fuse #[first, second] {} goal.mvarId! { maxSuggestions := 0 }
  unless empty.isEmpty do throwError "zero requested premises ignored"
  let mutating : Selector := fun g _ => do
    g.assign (mkConst ``True.intro)
    return #[{ name := `SelectorFixture.keep, score := 1.0 }]
  let observes : Selector := fun g _ => do
    if ← g.isAssigned then throwError "constituent metavariable changes leaked"
    return #[{ name := `SelectorFixture.held, score := 1.0 }]
  discard <| fuse #[mutating, observes] {} goal.mvarId! {}
  if ← goal.mvarId!.isAssigned then throwError "fusion modified the caller goal"

run_cmd liftTermElabM do
  let some path ← IO.getEnv "JEVSELECTOR_TEST_INDEX" | throwError "missing fixture index"
  let idx ← load path
  let eligible : Std.HashSet String := .ofArray idx.artifact.eligible
  let count := idx.artifact.declarations.foldl (fun n e =>
    if eligible.contains e.name then n + e.symbols.size else n) (0 : Nat)
  let expected := max 1 (count.toFloat / (max 1 eligible.size).toFloat)
  unless idx.meanSymbolCount == expected do
    throwError "length normalization used held-out statement statistics"
  let g ← mkFreshExprMVar (← inferType (mkConst ``SelectorFixture.held))
  let onlyHeld : LibrarySuggestions.Config := {
    maxSuggestions := 1, filter := fun n => pure (n == `SelectorFixture.held) }
  let uniform ← idx.selector {} g.mvarId! onlyHeld
  let focused ← idx.selector { targetWeight := 4 } g.mvarId! onlyHeld
  let [uniform] := uniform.toList | throwError "missing uniform suggestion"
  let [focused] := focused.toList | throwError "missing focused suggestion"
  unless focused.score > uniform.score do
    throwError "target symbols did not receive their configured weight"
  withLocalDeclD `background (mkConst ``True) fun _ => do
    let firstGoal ← mkFreshExprMVar (← g.mvarId!.getType)
    let first ← idx.targetSelector firstGoal.mvarId! {}
    withLocalDeclD `duplicate (mkConst ``True) fun _ => do
      let secondGoal ← mkFreshExprMVar (← g.mvarId!.getType)
      let second ← idx.targetSelector secondGoal.mvarId! {}
      unless first.map (fun x => (x.name, x.score)) ==
          second.map (fun x => (x.name, x.score)) do
        throwError "duplicate context facts changed retrieval"
  for selector in #[idx.targetSelector, idx.ensembleSelector] do
    let result ← selector g.mvarId! {
      maxSuggestions := 1, filter := fun n => pure (n == `SelectorFixture.later) }
    unless result.map (·.name) == #[`SelectorFixture.later] do
      throwError "experimental retrieval truncated before the caller filter"
  let invalid ← try
    discard <| idx.selector { targetWeight := -1 } g.mvarId! {}
    pure false
  catch _ => pure true
  unless invalid do throwError "negative query weight accepted"
