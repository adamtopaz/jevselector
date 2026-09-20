import JevSelector.Structural

open Lean Meta Elab Command JevSelector LibrarySuggestions

namespace StructuralFixture
inductive P : Nat → Prop where
  | intro (n : Nat) : P n
theorem any (n : Nat) : P n := P.intro n
theorem seven : P 7 := P.intro 7
theorem iffSelf (n : Nat) : P n ↔ P n := Iff.rfl
end StructuralFixture

run_cmd liftTermElabM do
  let idx ← StructuralIndex.create
  idx.warmup
  let isolated ← idx.freshCache
  let some originalTree ← idx.tree.get | throwError "missing initialized tree"
  let pendingBefore := originalTree.tries.map (·.pending.size)
  let probe ← mkFreshExprMVar (← inferType (mkConst ``Nat.add_comm))
  let copyResult ← isolated.selector {} probe.mvarId! {
    filter := fun n => pure (n == ``Nat.add_comm) }
  unless copyResult.map (·.name) == #[``Nat.add_comm] do
    throwError "independent structural cache could not retrieve"
  let some originalAfter ← idx.tree.get | throwError "base cache disappeared"
  unless originalAfter.tries.map (·.pending.size) == pendingBefore do
    throwError "query refinement warmed another cache"
  isolated.tree.set none
  unless (← idx.tree.get).isSome do throwError "cache references are aliased"
  let goal ← mkFreshExprMVar (mkApp (mkConst ``StructuralFixture.P) (mkNatLit 7))
  let selected ← idx.selector {} goal.mvarId! {
    maxSuggestions := 2,
    filter := fun n => pure (n == ``StructuralFixture.any || n == ``StructuralFixture.seven) }
  unless selected.map (·.name) == #[``StructuralFixture.seven, ``StructuralFixture.any] do
    throwError "structural specificity ranking or filtering failed"
  let iffResult ← idx.selector {} goal.mvarId! {
    filter := fun n => pure (n == ``StructuralFixture.iffSelf) }
  unless iffResult.map (·.name) == #[``StructuralFixture.iffSelf] do
    throwError "iff directions were omitted or duplicated"
  let future ← idx.selector {} goal.mvarId! {
    filter := fun n => pure (n == `StructuralFixture.later) }
  unless future.isEmpty do throwError "future declaration returned"
  let empty ← idx.selector {} goal.mvarId! { maxSuggestions := 0 }
  unless empty.isEmpty do throwError "zero suggestion request ignored"
  if ← goal.mvarId!.isAssigned then throwError "structural query assigned caller goal"
  let quantified ← mkFreshExprMVar (← inferType (mkConst ``Nat.add_comm))
  let imported ← idx.selector {} quantified.mvarId! {
    filter := fun n => pure (n == ``Nat.add_comm) }
  unless imported.map (·.name) == #[``Nat.add_comm] do
    throwError "imported or quantified matching failed"
  let badTree ← forallTelescope (← quantified.mvarId!.getType) fun _ conclusion => do
    let e ← LazyDiscrTree.InitEntry.fromExpr conclusion
      ({ name := ``Nat.add_comm, typeHash := 0 } : StructuralPremise)
    let tree : LazyDiscrTree.PreDiscrTree StructuralPremise := {}
    pure (tree.push e.key e.entry).toLazy
  let stale := { idx with tree := ← IO.mkRef (some badTree) }
  let hashRejected ← try
    discard <| stale.selector {} quantified.mvarId! {
      filter := fun n => pure (n == ``Nat.add_comm) }
    pure false
  catch _ => pure true
  unless hashRejected do throwError "stale imported signature hash accepted"
  let boundRejected ← try
    discard <| idx.selector { heartbeats := 0 } goal.mvarId! {}
    pure false
  catch _ => pure true
  unless boundRejected do throwError "unbounded query accepted"
  let changed := { idx with importedModules := #[] }
  let importsRejected ← try
    discard <| changed.selector {} goal.mvarId! {}
    pure false
  catch _ => pure true
  unless importsRejected do throwError "changed imported environment accepted"
  let beforeDeny ← saveState
  modifyEnv fun env => nameDenyListExt.addEntry env "StructuralFixture"
  let denied ← idx.selector {} goal.mvarId! {
    filter := fun n => pure ((`StructuralFixture).isPrefixOf n) }
  unless denied.isEmpty do throwError "updated name deny list ignored"
  beforeDeny.restore
  modifyEnv fun env => moduleDenyListExt.addEntry env "Init"
  let deniedImport ← idx.selector {} quantified.mvarId! {
    filter := fun n => pure (n == ``Nat.add_comm) }
  unless deniedImport.isEmpty do throwError "updated module deny list ignored"
  beforeDeny.restore
  modifyEnv fun env => typePrefixDenyListExt.addEntry env ``StructuralFixture.P
  let deniedType ← idx.selector {} goal.mvarId! {
    filter := fun n => pure (n == ``StructuralFixture.any || n == ``StructuralFixture.seven) }
  unless deniedType.isEmpty do throwError "updated type-prefix deny list ignored"
  beforeDeny.restore

  let beforeLater ← saveState
  addDecl <| .axiomDecl {
    name := `StructuralFixture.later, levelParams := [],
    type := ← goal.mvarId!.getType, isUnsafe := false }
  let selected ← idx.selector {} goal.mvarId! {
    filter := fun n => pure (n == `StructuralFixture.later) }
  unless selected.map (·.name) == #[`StructuralFixture.later] do
    throwError "new earlier current-file signature was not indexed"
  beforeLater.restore
  let saved ← saveState
  addDecl <| .axiomDecl {
    name := `StructuralFixture.transient, levelParams := [],
    type := ← goal.mvarId!.getType, isUnsafe := false }
  let transient ← idx.selector {} goal.mvarId! {
    filter := fun n => pure (n == `StructuralFixture.transient) }
  unless transient.map (·.name) == #[`StructuralFixture.transient] do
    throwError "transient signature missing"
  saved.restore
  let rolledBack ← idx.selector {} goal.mvarId! {
    filter := fun n => pure (n == `StructuralFixture.transient) }
  unless rolledBack.isEmpty do throwError "rolled-back current-file declaration leaked"
  discard <| idx.selector {} goal.mvarId! { filter := fun _ => do
    if ← goal.mvarId!.isAssigned then throwError "caller filter state leaked"
    goal.mvarId!.assign (mkApp (mkConst ``StructuralFixture.P.intro) (mkNatLit 7))
    return true }
  if ← goal.mvarId!.isAssigned then throwError "mutating caller filter assigned goal"

theorem StructuralFixture.later : StructuralFixture.P 7 := StructuralFixture.P.intro 7
