module
public meta import JevSelector.Features
public meta import Lean.Elab.Command
public meta section
namespace JevSelector
open Lean Meta Elab Command LibrarySuggestions

structure ExportConfig where
  output : String
  scopes : Array String
  deriving FromJson

/-- Export theorem TYPES only. Never reads proof values or dependencies. -/
elab "#jevselector_export" : command => do
  let some path ← IO.getEnv "JEVSELECTOR_EXPORT_CONFIG"
    | throwError "set JEVSELECTOR_EXPORT_CONFIG to the preparation configuration"
  let cfg : ExportConfig ← IO.ofExcept (Json.parse (← IO.FS.readFile path) >>= fromJson?)
  let env ← getEnv
  let output ← IO.FS.Handle.mk cfg.output .write
  output.putStrLn <| (Json.mkObj [("kind", toJson "header"),
    ("leanVersion", toJson Lean.versionString),
    ("modules", toJson (env.header.moduleNames.map Name.toString))]).compress
  let names := env.constants.toList.map Prod.fst |>.toArray.qsort (fun a b => a.toString < b.toString)
  for name in names do
    let info := env.find? name |>.get!
    let mod := (moduleName env name).toString
    unless cfg.scopes.any (matchesScope mod) do continue
    let row := Json.mkObj [("kind", toJson "declaration"), ("name", toJson name.toString),
      ("moduleName", toJson mod)]
    output.putStrLn row.compress
    unless wasOriginallyTheorem env name && !isDeniedPremise env name do continue
    output.putStrLn <| ((toJson (entry env info)).mergeObj
      (Json.mkObj [("kind", toJson "theorem")])).compress
  output.flush
end JevSelector
