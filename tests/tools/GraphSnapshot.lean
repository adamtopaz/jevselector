import Lean
import JevSelector.DependencyGraph
open Lean Meta Elab Command JevSelector
set_option maxHeartbeats 4000000
run_cmd liftTermElabM do
  let some path ← IO.getEnv "JEVSELECTOR_GRAPH_SNAPSHOT" | throwError "missing snapshot output"
  let start ← IO.monoMsNow
  let graph ← DependencyGraph.create
  let elapsed := (← IO.monoMsNow) - start
  let rows := graph.entries.toArray.qsort (fun a b => Name.quickLt a.1 b.1)
  let forwards := graph.forwardEdges.toArray.qsort (fun a b => Name.quickLt a.1 b.1)
  let data := Json.mkObj [
    ("entries", .arr (rows.map fun (name, entry) => Json.mkObj [
      ("name", toJson name.toString), ("typeHash", toJson entry.typeHash.toNat),
      ("dependencies", toJson (entry.dependencies.map Name.toString))])),
    ("forward", .arr (forwards.map fun (name, edges) => Json.mkObj [
      ("name", toJson name.toString), ("edges", toJson (edges.map Name.toString))]))]
  IO.FS.writeFile path data.compress
  IO.eprintln s!"Graph snapshot: {graph.entries.size} entries in {elapsed}ms"
