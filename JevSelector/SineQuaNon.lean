module

public meta import Lean.LibrarySuggestions.SineQuaNon
public meta import Lean.LibrarySuggestions.SymbolFrequency

public meta section
namespace JevSelector.SineQuaNon
open Lean Meta LibrarySuggestions

/-- Settings for Lean's Sine Qua Non baseline; no prepared artifact is required. -/
structure Config where
  depthFactor : Float := 1.5
  /-- Cap on raw imported candidates, including duplicates and filtered names.
  Retrieval doubles its request when filtering leaves too few suggestions. -/
  maxCandidates : Nat := 1024
  includeCurrentFile : Bool := true
  deriving ToJson, FromJson

/-- Initialize the imported trigger and frequency maps outside a goal's clock.
Lean caches these for a fixed import environment; use separate processes when
benchmarking different import environments, as the benchmark driver does. -/
def warmup : CoreM Unit := do
  discard <| Lean.LibrarySuggestions.SineQuaNon.sineQuaNonTheorems ``True
  discard <| symbolFrequency ``True

private def imported (options : Config) : Selector := fun goal cfg => do
  if cfg.maxSuggestions == 0 || options.maxCandidates == 0 then return #[]
  let env ← getEnv
  let mut limit := min cfg.maxSuggestions options.maxCandidates
  let mut result := #[]
  while limit > 0 do
    let raw ← sineQuaNonSelector options.depthFactor goal { cfg with maxSuggestions := limit }
    let mut seen : Std.HashSet Name := {}
    result := #[]
    for suggestion in raw do
      let name := suggestion.name
      if seen.contains name then continue
      seen := seen.insert name
      if !env.contains name || isDeniedPremise env name ||
          !wasOriginallyTheorem env name || !(← cfg.filter name) then continue
      result := result.push suggestion
      if result.size >= cfg.maxSuggestions then break
    if result.size >= cfg.maxSuggestions || raw.size < limit ||
        limit == options.maxCandidates then break
    limit := min options.maxCandidates (2 * limit)
  return result

private def localTheorems : Selector := fun _ cfg => do
  let env ← getEnv
  let mut result := #[]
  -- Sort names so this supplement has a stable order independent of map layout.
  let names := env.constants.map₂.toArray.map (·.1) |>.qsort Name.quickLt
  for name in names do
    if result.size >= cfg.maxSuggestions then break
    if isDeniedPremise env name (allowPrivate := true) ||
        !wasOriginallyTheorem env name || !(← cfg.filter name) then continue
    result := result.push { name, score := 1 }
  return result

/-- Sine Qua Non retrieval with the standard selector contract. Imported
theorems keep Lean's priority order. Optional current-file theorems are
interleaved 1:1. Availability, caller filtering and deduplication precede the
final limit; the imported candidate cap can leave fewer results than requested. -/
def selector (options : Config := {}) : Selector := fun goal cfg => goal.withContext do
  if cfg.maxSuggestions == 0 then return #[]
  unless options.depthFactor.isFinite && options.depthFactor >= 1 do
    throwError "Sine Qua Non depthFactor must be finite and at least 1"
  let select := if options.includeCurrentFile then
    (imported options).intersperse localTheorems else imported options
  let raw ← select goal cfg
  let mut seen : Std.HashSet Name := {}
  let mut result := #[]
  for suggestion in raw do
    if seen.contains suggestion.name then continue
    seen := seen.insert suggestion.name
    result := result.push suggestion
  return result.take cfg.maxSuggestions

end JevSelector.SineQuaNon
