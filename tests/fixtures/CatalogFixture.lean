module
public import Init
public section
namespace CatalogFixture

def identity (n : Nat) : Nat := n

inductive Box where
  | mk : Nat → Box

-- A proof-valued definition may be a premise, but its body must never be a
-- training example or opened when traversing another theorem's proof.
def definitionProof : 0 + 1 = 1 := Nat.zero_add 1

theorem useDefinition : 0 + 1 = 1 := definitionProof

theorem held (n : Nat) : 0 + n = n := Nat.zero_add n

end CatalogFixture
