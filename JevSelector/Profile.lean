module
public meta import JevSelector.Index
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
  let start ← IO.monoMsNow
  let idx ← load indexPath
  let loadMs := (← IO.monoMsNow) - start
  let timings ← liftTermElabM do
    idx.validateEnvironment
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
          let result ← idx.selector {} goal.mvarId! { filter := fun n => pure (n != name) }
          rows := rows.push <| Json.mkObj [("name", toJson e.name),
            ("elapsedNanos", toJson ((← IO.monoNanosNow) - start)), ("returned", toJson result.size)]
        finally saved.restore
    return rows
  IO.FS.writeFile output <| (Json.mkObj [("schema", toJson (1 : Nat)),
    ("kind", toJson "query-latency-only"), ("loadMs", toJson loadMs),
    ("queries", .arr timings), ("provenance", idx.artifact.provenance)]).compress
end JevSelector
