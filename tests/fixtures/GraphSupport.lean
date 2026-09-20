module
public meta import JevSelector.DependencyGraph
public meta import GraphFixture
public meta section
namespace GraphTestSupport
open Lean JevSelector

initialize graphForTests : IO.Ref (Option DependencyGraph) ← IO.mkRef none
initialize graphEarlierEnv : IO.Ref (Option Environment) ← IO.mkRef none

end GraphTestSupport
