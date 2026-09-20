module
public meta import JevSelector.ProofDependencies
public meta import JevSelector.Usage
public meta import JevSelector.Closing
public meta import JevSelector.Structural
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
  let dependencies ← match (cfg.getObjValAs? String "dependencies").toOption with
    | none => pure none
    | some path => some <$> loadDependencies idx path
  let usage ← match (cfg.getObjValAs? String "usage").toOption with
    | none => pure none
    | some path => some <$> loadUsage idx path
  let loadMs := (← IO.monoMsNow) - start
  IO.eprintln s!"JevSelector index loaded in {loadMs}ms"
  let (timings, structuralInitMs) ← liftTermElabM do
    idx.validateEnvironment
    if let some model := dependencies then model.validateEnvironment
    if let some model := usage then model.validateEnvironment
    let structuralStart ← IO.monoMsNow
    let structural ← if method == "structural" || method == "structural-target" ||
        method == "rewrites" || method == "rewrites-target" then do
      let mode := if method == "rewrites" || method == "rewrites-target" then
        StructuralMode.rewrites else StructuralMode.conclusion
      let model ← StructuralIndex.create mode
      model.warmup
      pure (some model)
    else pure none
    let structuralStop ← IO.monoMsNow
    let structuralInitMs := if structural.isSome then structuralStop - structuralStart else 0
    let selector ← match method with
      | "sparse" => pure (idx.selector {})
      | "target" => pure idx.targetSelector
      | "closing-target" => pure (closingFirst idx.targetSelector)
      | "structural" | "rewrites" => match structural with
        | some model => pure (model.selector {})
        | none => throwError "JevSelector: structural index was not initialized"
      | "structural-target" | "rewrites-target" => match structural with
        | some model => pure (fuse #[idx.targetSelector, model.selector {}] {})
        | none => throwError "JevSelector: structural index was not initialized"
      | "ensemble" => pure (idx.ensembleSelector {})
      | "neighbors" => match dependencies with
        | some model => pure (model.selector {})
        | none => throwError "JevSelector: neighbors profiling requires a dependency artifact"
      | "proof-hybrid" => match dependencies with
        | some model => pure (model.hybridSelector {})
        | none => throwError "JevSelector: proof-hybrid profiling requires a dependency artifact"
      | "usage" => match usage with
        | some model => pure (model.selector {})
        | none => throwError "JevSelector: usage profiling requires a usage artifact"
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
    return (rows, structuralInitMs)
  IO.FS.writeFile output <| (Json.mkObj [("schema", toJson (1 : Nat)),
    ("kind", toJson "query-latency-only"), ("loadMs", toJson loadMs),
    ("structuralInitMs", toJson structuralInitMs),
    ("method", toJson method),
    ("queries", .arr timings), ("provenance", idx.artifact.provenance)]).compress
end JevSelector
