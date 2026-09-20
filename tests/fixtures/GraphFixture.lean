module
public import Init
public section
namespace GraphFixture

@[expose] def marker (n : Nat) : Nat := n
-- This reference exists only in a body, never in the declaration's type.
def bodyOnly : Nat → Nat := marker

theorem forwardEdge (n : Nat) : marker n = n := rfl
theorem anotherEdge : marker 0 = 0 := rfl
private theorem hiddenEdge : marker 2 = 2 := rfl

end GraphFixture
