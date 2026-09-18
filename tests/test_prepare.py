import unittest
from jevselector.cli import fit


def corpus():
    yield {"kind": "header", "leanVersion": "test", "modules": ["Example"]}
    for n, symbols in [("Example.a", ["Nat", "Eq"]), ("Example.b", ["Nat", "LE"]),
                       ("Example.b.helper", ["Rare"]), ("Example.c", ["Eq"])]:
        yield {"kind": "declaration", "name": n, "moduleName": "Example"}
        yield {"kind": "theorem", "name": n, "moduleName": "Example", "typeHash": 0, "symbols": symbols}


class Preparation(unittest.TestCase):
    def test_holdouts_precede_statistics(self):
        artifact = fit(corpus(), {"schema": 1, "declarations": ["Example.b"]})
        self.assertEqual(artifact["eligible"], ["Example.a", "Example.c"])
        self.assertEqual(artifact["excluded"], ["Example.b", "Example.b.helper"])
        self.assertEqual(len(artifact["declarations"]), 4)
        self.assertNotIn("Rare", {w["symbol"] for w in artifact["weights"]})
        self.assertNotIn("LE", {w["symbol"] for w in artifact["weights"]})

    def test_full_and_empty(self):
        self.assertEqual(fit(corpus()), fit(corpus(), {"schema": 1}))

    def test_module(self):
        artifact = fit(corpus(), {"schema": 1, "modules": ["Example"]})
        self.assertEqual(artifact["eligible"], [])
        self.assertEqual(artifact["weights"], [])

    def test_stale(self):
        for key in ["declarations", "modules"]:
            with self.assertRaisesRegex(ValueError, "unresolved"):
                fit(corpus(), {"schema": 1, key: ["Missing"]})

if __name__ == "__main__":
    unittest.main()
