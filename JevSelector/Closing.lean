module
public meta import JevSelector.Index
public meta import Lean.Meta.Tactic.Apply
public meta import Lean.Meta.Tactic.Assumption
public meta import Lean.Meta.Tactic.Refl
public meta section
namespace JevSelector
open Lean Meta LibrarySuggestions

/-- CPU work limits for speculative one-premise closure. This is a ranking
experiment, not an alternative proof certificate or a trained probability. -/
structure ClosingConfig where
  /-- Retrieve at most this many names, including when the caller requests more. -/
  maxPool : Nat := 100
  /-- Probe only this prefix of the filtered, deduplicated ranking. -/
  maxProbes : Nat := 64
  /-- Lean's user-facing heartbeat units, per probe; zero is rejected. -/
  heartbeats : Nat := 1000
  /-- Discharge at most this many application subgoals. -/
  maxSubgoals : Nat := 4

private def closesWith (goal : MVarId) (name : Name) (cfg : ClosingConfig) : MetaM Bool := do
  let _ : MonadExceptOf Exception MetaM :=
    { (inferInstance : MonadExceptOf Exception MetaM) with tryCatch := tryCatchRuntimeEx }
  let saved ← saveState
  try
    withOptions (·.set `maxHeartbeats cfg.heartbeats) <|
      withTheReader Core.Context (fun c => { c with maxHeartbeats := cfg.heartbeats * 1000 }) <|
      withCurrHeartbeats <| goal.withContext do
        let probe ← mkFreshExprMVar (← goal.getType)
        let pending ← probe.mvarId!.apply (← mkConstWithFreshMVarLevels name)
        if pending.length > cfg.maxSubgoals then return false
        for g in pending do
          if ← g.isAssigned then continue
          let beforeAssumption ← saveState
          if !(← g.assumptionCore) then
            beforeAssumption.restore
            g.refl
        let proof ← instantiateMVars probe
        return !proof.hasExprMVar && !proof.hasSorry
  catch _ => return false
  finally saved.restore

/-- Promote premises whose application can close the goal with local assumptions
or reflexivity. All other names retain their relative order, including useful
rewrite/unfolding premises that do not apply directly. Speculation restores Lean
state after every probe and after the base selector; no proof terms cross those
snapshots. The returned scores encode rank, not calibrated probabilities.

All retrieval and probing happens inside the caller's timing budget. This wrapper
does not access proof bodies, fit data, or call a model. -/
def closingFirst (base : Selector) (options : ClosingConfig := {}) : Selector :=
    fun goal cfg => do
  if cfg.maxSuggestions == 0 then return #[]
  if options.maxPool == 0 || options.heartbeats == 0 then
    throwError "JevSelector: closing pool and heartbeat bounds must be positive"
  let saved ← saveState
  try
    let pool := min options.maxPool (max cfg.maxSuggestions options.maxProbes)
    let beforeBase ← saveState
    let suggestions ← try base goal { cfg with maxSuggestions := pool }
      finally beforeBase.restore
    let env ← getEnv
    let mut seen : Std.HashSet Name := {}
    let mut candidates : Array Suggestion := #[]
    for s in suggestions.take pool do
      if seen.contains s.name || !env.contains s.name || isDeniedPremise env s.name then continue
      let beforeFilter ← saveState
      let allowed ← try cfg.filter s.name finally beforeFilter.restore
      unless allowed do continue
      seen := seen.insert s.name
      candidates := candidates.push s
    let mut closed : Array Suggestion := #[]
    let mut rest : Array Suggestion := #[]
    for (s, i) in candidates.zipIdx do
      if i < options.maxProbes && (← closesWith goal s.name options) then
        closed := closed.push s
      else rest := rest.push s
    return ((closed ++ rest).take cfg.maxSuggestions).mapIdx fun i s =>
      { s with score := 1 / (i + 1).toFloat }
  finally saved.restore

end JevSelector
