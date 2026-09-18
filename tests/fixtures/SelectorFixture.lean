namespace SelectorFixture

theorem keep (n : Nat) : n + 0 = n := Nat.add_zero n
theorem held (n : Nat) : 0 + n = n := Nat.zero_add n
theorem later (n : Nat) : n = n := rfl

end SelectorFixture
