module
public meta import JevSelector.Ensemble
public meta import Lean.Elab.Command
public meta section
namespace JevSelector
open Lean Meta Elab Command

/-- Query-latency smoke profile, not a proof-coverage benchmark. Reads
JEVSELECTOR_PROFILE_CONFIG: index, output, samples, repeats. -/
elab "#jevselector_profile" : command => do
  let some path ← IO.getEnv "JEVSELECTOR_PROFILE_CONFIG" | throwError "missing profile config"
  let cfg ← IO.ofExcept (Json.parse (← IO.FS.readFile path))
  let indexPath ← ofExcept (cfg.getObjValAs? String "index")
  let output ← ofExcept (cfg.getObjValAs? String "output")
  let samples ← ofExcept (cfg.getObjValAs? Nat "samples")
  let repeats ← ofExcept (cfg.getObjValAs? Nat "repeats")
  let method := (cfg.getObjValAs? String "method").toOption.getD "sparse"
  let start ← IO.monoMsNow
  let idx ← load indexPath
  let loadMs := (← IO.monoMsNow) - start
  IO.eprintln s!"JevSelector index loaded in {loadMs}ms"
  let timings ← liftTermElabM do
    idx.validateEnvironment
    let selector ← match method with
      | "sparse" => pure (idx.selector {})
      | "target" => pure idx.targetSelector
      | "ensemble" => pure (idx.ensembleSelector {})
      | _ => throwError "JevSelector: unknown profiling method {method}"
    let mut rows := #[]
    let count := min samples idx.artifact.declarations.size
    for i in [:count] do
      let e := idx.artifact.declarations[i * idx.artifact.declarations.size / count]!
      let name := e.name.toName
      let some info := (← getEnv).find? name | continue
      for _ in [:repeats] do
        let saved ← saveState
        try
          let goal ← mkFreshExprMVar info.type
          let start ← IO.monoNanosNow
          let result ← selector goal.mvarId! { filter := fun n => pure (n != name) }
          let elapsed := (← IO.monoNanosNow) - start
          rows := rows.push <| Json.mkObj [("name", toJson e.name),
            ("elapsedNanos", toJson elapsed), ("returned", toJson result.size)]
          IO.eprintln s!"Profile {e.name}: {elapsed / 1000000}ms"
        finally saved.restore
    return rows
  IO.FS.writeFile output <| (Json.mkObj [("schema", toJson (1 : Nat)),
    ("kind", toJson "query-latency-only"), ("loadMs", toJson loadMs),
    ("method", toJson method),
    ("queries", .arr timings), ("provenance", idx.artifact.provenance)]).compress
end JevSelector
