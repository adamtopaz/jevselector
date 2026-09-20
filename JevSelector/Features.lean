module
public meta import Lean.LibrarySuggestions.Basic
public meta section
namespace JevSelector
open Lean Meta

/-- Signature-only adaptation of Lean 4.33's `LibrarySuggestions.isDeniedPremise`
(Apache-2.0, Lean FRO). The caller must establish availability and supply the live
type. Avoid `Environment.find?`, which waits for an asynchronous theorem's body
even though the public deny policy only needs its signature. -/
def isDeniedSignature (env : Environment) (name : Name) (type : Expr) : Bool := Id.run do
  if name == ``sorryAx || name.isInternalDetail || isInstanceReducibleCore env name ||
      Lean.Linter.isDeprecated env name then return true
  if (LibrarySuggestions.nameDenyListExt.getState env).any (fun p => name.anyS (· == p)) then
    return true
  if let some moduleIdx := env.getModuleIdxFor? name then
    if LibrarySuggestions.isDeniedModule env (env.header.moduleNames[moduleIdx.toNat]!) then
      return true
  if let .const head _ := type.getForallBody.getAppFn then
    if (LibrarySuggestions.typePrefixDenyListExt.getState env).any (·.isPrefixOf head) then
      return true
  return false

/-- Lean's derived JSON readers do not apply structure-field defaults. Add only
missing optional keys; present malformed values must still be rejected. -/
def jsonDefaults (value : Json) (fields : List (String × Json)) : Json :=
  fields.foldl (fun result (key, fallback) =>
    if (result.getObjVal? key).isOk then result
    else result.mergeObj (Json.mkObj [(key, fallback)])) value

def symbols (type : Expr) : Array Name :=
  type.getUsedConstants.qsort (fun a b => a.toString < b.toString)

def moduleName (env : Environment) (name : Name) : Name :=
  match env.getModuleIdxFor? name with
  | some idx => env.header.moduleNames[idx.toNat]!
  | none => env.header.mainModule

def matchesScope (moduleName scope : String) : Bool :=
  moduleName == scope || (scope ++ ".").isPrefixOf moduleName

structure Entry where
  name : String
  moduleName : String
  typeHash : Nat
  symbols : Array String
  deriving Inhabited, FromJson, ToJson

def entry (env : Environment) (info : ConstantInfo) : Entry := {
  name := info.name.toString
  moduleName := (moduleName env info.name).toString
  typeHash := (hash info.type).toNat
  symbols := (symbols info.type).map Name.toString }

end JevSelector
