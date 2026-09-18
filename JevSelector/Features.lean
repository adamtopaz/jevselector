module
public meta import Lean.LibrarySuggestions.Basic
public meta section
namespace JevSelector
open Lean Meta

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
