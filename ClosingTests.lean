import JevSelector.Closing

open Lean Meta Elab Command JevSelector LibrarySuggestions

namespace ClosingFixture
theorem reflexive (n : Nat) : n = n := rfl
theorem fromHypothesis (P Q : Prop) (h : P → Q) (p : P) : Q := h p
theorem moreWork (P Q : Prop) (h : P ∧ Q) : Q := h.2
theorem fromReflexivity (n : Nat) (_h : n = n) : n + 0 = n := Nat.add_zero n
end ClosingFixture

run_cmd liftTermElabM do
  let base : Selector := fun _ _ => pure #[
    { name := ``ClosingFixture.moreWork, score := 0.9, flag := some "←" },
    { name := ``ClosingFixture.reflexive, score := 0.8 },
    { name := ``ClosingFixture.fromHypothesis, score := 0.1 }]
  withLocalDeclD `P (mkSort .zero) fun p =>
    withLocalDeclD `Q (mkSort .zero) fun q =>
    withLocalDeclD `hp p fun _ => do
    withLocalDeclD `hpq (← mkArrow p q) fun _ => do
      let goal ← mkFreshExprMVar q
      let selected ← closingFirst base {} goal.mvarId! {}
      unless selected.map (·.name) == #[``ClosingFixture.fromHypothesis,
          ``ClosingFixture.moreWork, ``ClosingFixture.reflexive] do
        throwError "closure did not promote a useful premise or preserve tail order"
      unless (selected[1]?.map (·.flag)) == some (some "←") do throwError "lost suggestion flag"
      if ← goal.mvarId!.isAssigned then throwError "probe assigned caller goal"
      let bounded ← closingFirst base { maxProbes := 1 } goal.mvarId! {}
      unless bounded.map (·.name) == (← base goal.mvarId! {}).map (·.name) do
        throwError "probe prefix bound ignored"
      let noSubgoals ← closingFirst base { maxSubgoals := 0 } goal.mvarId! {}
      unless noSubgoals.map (·.name) == bounded.map (·.name) do
        throwError "subgoal bound ignored"
      let filtered ← closingFirst base {} goal.mvarId! {
        maxSuggestions := 1, filter := fun n => pure (n == ``ClosingFixture.reflexive) }
      unless filtered.map (·.name) == #[``ClosingFixture.reflexive] do
        throwError "caller filter not applied before truncation"
      discard <| closingFirst base {} goal.mvarId! {
        filter := fun _ => do
          if ← goal.mvarId!.isAssigned then throwError "filter state leaked between candidates"
          goal.mvarId!.assign (mkConst ``True.intro)
          return true }
      let tinyPool ← closingFirst base { maxPool := 1 } goal.mvarId! {}
      unless tinyPool.map (·.name) == #[``ClosingFixture.moreWork] do
        throwError "retrieval pool bound ignored"

run_cmd liftTermElabM do
  let goal ← mkFreshExprMVar (← mkEq (mkNatLit 7) (mkNatLit 7))
  let base : Selector := fun _ _ => pure #[
    { name := ``ClosingFixture.moreWork, score := 0.9 },
    { name := ``ClosingFixture.fromReflexivity, score := 0.1 }]
  let selected ← closingFirst base {} goal.mvarId! {}
  unless (selected.map (·.name))[0]! == ``ClosingFixture.fromReflexivity do
    throwError "reflexivity failed to discharge an application subgoal"
  if ← goal.mvarId!.isAssigned then throwError "reflexivity mutated caller goal"

run_cmd liftTermElabM do
  let n ← mkFreshExprMVar (mkConst ``Nat)
  let goal ← mkFreshExprMVar (← mkEq n (mkNatLit 7))
  let mutating : Selector := fun g _ => do
    g.assign (← mkEqRefl (mkNatLit 8))
    return #[{ name := `Unavailable.future, score := 1 },
      { name := ``ClosingFixture.reflexive, score := 0.5 },
      { name := ``ClosingFixture.reflexive, score := 0.4 }]
  let selected ← closingFirst mutating {} goal.mvarId! {}
  unless selected.map (·.name) == #[``ClosingFixture.reflexive] do
    throwError "failed availability or duplicate filtering"
  if (← goal.mvarId!.isAssigned) || (← n.mvarId!.isAssigned) then
    throwError "base selector or probe mutated caller metavariables"
  let empty ← closingFirst mutating {} goal.mvarId! { maxSuggestions := 0 }
  unless empty.isEmpty do throwError "zero request ignored"
  let rejected ← try
    discard <| closingFirst mutating { heartbeats := 0 } goal.mvarId! {}
    pure false
  catch _ => pure true
  unless rejected do throwError "unbounded heartbeats allowed"
