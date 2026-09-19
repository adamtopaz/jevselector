import copy
import math
import unittest

from jevselector.usage import fit_usage


def inputs():
    statements = {"schema": 1, "leanVersion": "test", "provenance": {"artifactId": "heldout-index"},
        "eligible": ["Example.a", "Example.b"], "excluded": ["Example.held"],
        "declarations": [
            {"name": "Example.a", "symbols": ["Common", "Rare"]},
            {"name": "Example.b", "symbols": ["Common"]},
            {"name": "Example.held", "symbols": ["Leaked"]}]}
    dependencies = {"schema": 1, "leanVersion": "test", "statementArtifactId": "heldout-index",
        "examples": [{"owner": "Example.a", "dependencies": ["Example.lemma"]},
                     {"owner": "Example.b", "dependencies": []}],
        "premises": [{"name": "Example.lemma", "typeHash": 7}]}
    return statements, dependencies


class Usage(unittest.TestCase):
    def test_exact_smoothed_weights(self):
        s, d = inputs()
        model = fit_usage(s, d)
        self.assertEqual(model["symbols"], ["Common", "Rare"])
        p = model["premises"][0]
        self.assertAlmostEqual(p["logPrior"], math.log(2 / 4))
        self.assertAlmostEqual(p["logNormalizer"], math.log1p(2 / 20))
        weights = {model["symbols"][f["symbol"]]: f["weight"] for f in p["features"]}
        self.assertAlmostEqual(weights["Common"], math.log1p(3 / 40))
        self.assertAlmostEqual(weights["Rare"], math.log1p(3 / 20))

    def test_pruning_keeps_full_normalizer(self):
        s, d = inputs()
        p = fit_usage(s, d, max_features=1)["premises"][0]
        self.assertEqual([f["symbol"] for f in p["features"]], [1])
        self.assertAlmostEqual(p["logNormalizer"], math.log1p(2 / 20))
        self.assertEqual(len(fit_usage(s, d, max_features=0)["premises"][0]["features"]), 2)

    def test_excluded_missing_duplicate_examples_rejected(self):
        s, d = inputs()
        for row in [{"owner": "Example.held", "dependencies": ["Example.lemma"]}, d["examples"][0]]:
            bad = copy.deepcopy(d)
            bad["examples"].append(row)
            with self.assertRaisesRegex(ValueError, "ineligible"):
                fit_usage(s, bad)
        d["examples"].pop()
        with self.assertRaisesRegex(ValueError, "incomplete"):
            fit_usage(s, d)

    def test_label_is_not_its_own_training_example(self):
        s, d = inputs()
        d["premises"][0]["name"] = "Example.held"
        d["examples"][0]["dependencies"] = ["Example.held"]
        model = fit_usage(s, d)
        self.assertNotIn("Example.held", model["exampleOwners"])
        self.assertNotIn("Leaked", model["symbols"])

    def test_identity_and_parameters(self):
        s, d = inputs()
        for mass in [0, -1, float("inf"), float("nan")]:
            with self.assertRaises(ValueError):
                fit_usage(s, d, smoothing_mass=mass)
        with self.assertRaises(ValueError):
            fit_usage(s, d, max_features=-1)
        d["statementArtifactId"] = "another-index"
        with self.assertRaises(ValueError):
            fit_usage(s, d)

    def test_empty_vocabulary(self):
        s, d = inputs()
        for row in s["declarations"]:
            row["symbols"] = []
        model = fit_usage(s, d)
        self.assertEqual(model["symbols"], [])
        self.assertEqual(model["premises"][0]["features"], [])
        self.assertEqual(model["premises"][0]["logNormalizer"], 0)
