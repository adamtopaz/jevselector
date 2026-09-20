import JevSelector.Structural

open Lean Meta Elab Command JevSelector LibrarySuggestions

namespace RewriteFixture
axiom f : Nat → Nat
axiom g : Nat → Nat
axiom p : Nat → Prop
axiom q : Nat → Prop
axiom bridge (n : Nat) : f n = g n
axiom functionBridge : f = g
axiom reverseBridge (n : Nat) : g n = f n
axiom equivalence (n : Nat) : p n ↔ q n
end RewriteFixture

run_cmd liftTermElabM do
  let idx ← StructuralIndex.create .rewrites
  idx.warmup
  let importedCopy ← idx.freshCache
  let some initialTree ← idx.tree.get | throwError "missing rewrite tree"
  let pendingBefore := initialTree.tries.map (·.pending.size)
  let importedGoal ← mkFreshExprMVar (← inferType (mkConst ``Nat.add_comm))
  let imported ← importedCopy.selector {} importedGoal.mvarId! {
    filter := fun n => pure (n == ``Nat.add_comm) }
  unless imported.map (·.name) == #[``Nat.add_comm] do
    throwError "imported rewrite signature omitted"
  let some afterCopyQuery ← idx.tree.get | throwError "base rewrite cache disappeared"
  unless afterCopyQuery.tries.map (·.pending.size) == pendingBefore do
    throwError "rewrite query refinement warmed another cache"
  let f := mkApp (mkConst ``RewriteFixture.f) (mkNatLit 7)
  let g := mkApp (mkConst ``RewriteFixture.g) (mkNatLit 7)
  let p := mkApp (mkConst ``RewriteFixture.p) f
  let q := mkApp (mkConst ``RewriteFixture.q) g
  let goal ← mkFreshExprMVar (mkApp2 (mkConst ``And) p q)
  let select (goal : Expr) (options : StructuralConfig := {}) :=
    idx.selector options goal.mvarId! { filter := fun n => pure (n == ``RewriteFixture.bridge) }
  let result ← select goal
  unless result.map (·.name) == #[``RewriteFixture.bridge] do
    throwError "proper subexpression rewrite omitted or repeated"
  let functionResult ← idx.selector {} goal.mvarId! {
    filter := fun n => pure (n == ``RewriteFixture.functionBridge) }
  unless functionResult.map (·.name) == #[``RewriteFixture.functionBridge] do
    throwError "application-head function equality omitted"
  if ← goal.mvarId!.isAssigned then throwError "rewrite query assigned caller goal"
  let backward ← mkFreshExprMVar (mkApp (mkConst ``RewriteFixture.p) g)
  unless (← select backward).map (·.name) == #[``RewriteFixture.bridge] do
    throwError "backward rewrite pattern omitted"
  let forward ← mkFreshExprMVar p
  let directional ← idx.selector {} forward.mvarId! {
    filter := fun n => pure (n == ``RewriteFixture.bridge || n == ``RewriteFixture.reverseBridge) }
  unless directional.map (·.name) == #[``RewriteFixture.bridge, ``RewriteFixture.reverseBridge] do
    throwError "forward rewrite weight was not applied"
  let iffGoal ← mkFreshExprMVar (mkApp (mkConst ``RewriteFixture.q) (mkNatLit 7))
  let iffResult ← idx.selector {} iffGoal.mvarId! {
    filter := fun n => pure (n == ``RewriteFixture.equivalence) }
  unless iffResult.map (·.name) == #[``RewriteFixture.equivalence] do
    throwError "iff rewrite pattern omitted"
  unless (← select goal { maxQueries := 1 }).isEmpty do
    throwError "rewrite query bound ignored"
  unless (← select goal { maxNodes := 1 }).isEmpty do
    throwError "rewrite node bound ignored"
  unless (← select goal { maxDepth := 1 }).isEmpty do
    throwError "rewrite depth bound ignored"
  let invalid ← try
    discard <| select goal { maxQueries := 0 }
    pure false
  catch _ => pure true
  unless invalid do throwError "unbounded rewrite query accepted"
  withLocalDeclD `n (mkConst ``Nat) fun n => do
    let body := mkApp (mkConst ``RewriteFixture.p) (mkApp (mkConst ``RewriteFixture.f) n)
    let quantified ← mkFreshExprMVar (← mkForallFVars #[n] body)
    unless (← select quantified).map (·.name) == #[``RewriteFixture.bridge] do
      throwError "rewrite query lost binder scope"
  withLocalDeclD `h p fun _ => do
    let contextGoal ← mkFreshExprMVar (mkConst ``True)
    unless (← select contextGoal).map (·.name) == #[``RewriteFixture.bridge] do
      throwError "local hypothesis rewrite omitted"
    unless (← select contextGoal { maxHypotheses := 0 }).isEmpty do
      throwError "hypothesis bound ignored"
  let original ← idx.tree.get
  let copy ← idx.freshCache
  unless copy.mode == .rewrites do throwError "rewrite cache copy lost mode"
  copy.tree.set none
  unless (← idx.tree.get).isSome && original.isSome do
    throwError "rewrite caches alias mutable references"
  let before ← saveState
  addDecl <| .axiomDecl {
    name := `RewriteFixture.transient, levelParams := [],
    type := ← mkEq f g, isUnsafe := false }
  let cfg : LibrarySuggestions.Config := { filter := fun n => pure (n == `RewriteFixture.transient) }
  unless (← idx.selector {} goal.mvarId! cfg).size == 1 do
    throwError "new current-file rewrite omitted"
  before.restore
  unless (← idx.selector {} goal.mvarId! cfg).isEmpty do
    throwError "rolled-back rewrite leaked"
  discard <| idx.selector {} goal.mvarId! { filter := fun _ => do
    if ← goal.mvarId!.isAssigned then throwError "rewrite filter state leaked"
    goal.mvarId!.assign (← mkFreshExprMVar (← goal.mvarId!.getType))
    return true }
  if ← goal.mvarId!.isAssigned then throwError "rewrite filter assigned caller goal"
