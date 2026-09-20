import unittest
import tempfile
from pathlib import Path
from jevselector.cli import package_directory
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

    def test_quoted_package_directory(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            package = root / ".lake/packages/premise-selection/nested"
            package.mkdir(parents=True)
            self.assertEqual(package_directory(root, {}, {"type": "git", "name": "«premise-selection»", "subDir": "nested"}), package)
            with self.assertRaises(ValueError):
                package_directory(root, {}, {"type": "git", "name": "missing"})

    def test_stale(self):
        for key in ["declarations", "modules"]:
            with self.assertRaisesRegex(ValueError, "unresolved"):
                fit(corpus(), {"schema": 1, key: ["Missing"]})

    def test_public_candidates_do_not_change_fitted_statistics(self):
        original = list(corpus())
        extended = list(corpus())
        extended[0] = {**extended[0], "publicConstants": True}
        extended += [
            {"kind": "declaration", "name": "Example.definition", "moduleName": "Example"},
            {"kind": "candidate", "name": "Example.definition", "moduleName": "Example",
             "typeHash": 0, "symbols": ["NotAFittedFeature"]}]
        baseline, expanded = fit(original), fit(extended)
        self.assertEqual(baseline["eligible"], expanded["eligible"])
        self.assertEqual(baseline["weights"], expanded["weights"])
        self.assertEqual(expanded["candidateOnly"], ["Example.definition"])
        self.assertTrue(expanded["publicConstants"])
        held = fit(extended, {"schema": 1, "declarations": ["Example.definition"]})
        self.assertEqual(held["candidateOnly"], [])
        self.assertIn("Example.definition", held["excluded"])
        self.assertEqual(held["weights"], baseline["weights"])
        extended[0]["publicConstants"] = False
        with self.assertRaisesRegex(ValueError, "catalog"):
            fit(extended)

    def test_duplicate_catalog_entries_rejected(self):
        rows = list(corpus())
        with self.assertRaisesRegex(ValueError, "duplicate"):
            fit(rows + [rows[-1]])

if __name__ == "__main__":
    unittest.main()
