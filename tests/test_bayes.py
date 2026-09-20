import copy
import math
import unittest
from unittest.mock import patch

from jevselector.bayes import fit_bayes


def inputs():
    statements = {"schema": 1, "leanVersion": "test", "provenance": {"artifactId": "toy"},
        "eligible": ["a", "b", "lemma"], "excluded": ["held"],
        "declarations": [
            {"name": "a", "typeHash": 1, "symbols": ["Common", "Rare"]},
            {"name": "b", "typeHash": 2, "symbols": ["Common"]},
            {"name": "lemma", "typeHash": 3, "symbols": ["Own"]},
            {"name": "held", "typeHash": 4, "symbols": ["Leaked"]},
            {"name": "definition", "typeHash": 5, "symbols": ["Unfitted"]}],
        "publicConstants": True, "candidateOnly": ["definition"]}
    dependencies = {"schema": 1, "leanVersion": "test", "statementArtifactId": "toy",
        "examples": [{"owner": "a", "dependencies": ["lemma", "held"]},
                     {"owner": "b", "dependencies": ["lemma"]},
                     {"owner": "lemma", "dependencies": []}],
        "premises": [{"name": "lemma", "typeHash": 3}, {"name": "held", "typeHash": 4}]}
    return statements, dependencies


def sparse_score(header, premise, query):
    corrections = {header["symbols"][f["symbol"]]: f["weight"] for f in premise["features"]}
    return (premise["logPrior"] + sum(weight * header["missingWeight"] for weight in query.values())
            + sum(weight * corrections.get(feature, 0) for feature, weight in query.items()))


def direct_score(statements, dependencies, label, query, prior=20, observed=10, missing=-15):
    # Independent reference: explicitly enumerate weighted examples and evaluate
    # known/missing cases, without using the fitted sparse deltas.
    signatures = {r["name"]: set(r["symbols"]) for r in statements["declarations"]}
    examples = [(signatures[r["owner"]], 1) for r in dependencies["examples"]
                if label in r["dependencies"]]
    if label in statements["eligible"] and prior:
        examples.append((signatures[label], prior))
    support = sum(weight for _, weight in examples)
    result = math.log(support)
    for feature, weight in query.items():
        count = sum(w for features, w in examples if feature in features)
        result += weight * (math.log(observed * count / support) if count else missing)
    return result


class Bayes(unittest.TestCase):
    def test_sparse_scores_equal_direct_formula(self):
        s, d = inputs()
        for prior in [0, 0.5, 20]:
            header, premises = fit_bayes(s, d, signature_prior=prior, max_features=0)
            for query in [{}, {"Common": 1}, {"Rare": 4, "Own": 0.5}, {"Unknown": 2}]:
                for premise in premises:
                    self.assertAlmostEqual(sparse_score(header, premise, query),
                        direct_score(s, d, premise["name"], query, prior=prior), places=11)

    def test_held_out_label_never_receives_signature_prior(self):
        s, d = inputs()
        header, premises = fit_bayes(s, d)
        self.assertNotIn("held", header["exampleOwners"])
        self.assertNotIn("held", header["signaturePriorOwners"])
        self.assertNotIn("Leaked", header["symbols"])
        self.assertNotIn("Unfitted", header["symbols"])
        self.assertNotIn("definition", [p["name"] for p in premises])
        held = next(p for p in premises if p["name"] == "held")
        self.assertEqual(held["logPrior"], 0)
        self.assertEqual(next(p for p in premises if p["name"] == "lemma")["logPrior"], math.log(22))

    def test_signature_prior_can_be_disabled(self):
        s, d = inputs()
        header, premises = fit_bayes(s, d, signature_prior=0)
        self.assertEqual(header["signaturePriorOwners"], [])
        self.assertEqual([p["name"] for p in premises], ["held", "lemma"])

    def test_missing_and_duplicate_owners_rejected_before_counting(self):
        s, d = inputs()
        variants = [d["examples"][:-1], d["examples"] + [d["examples"][0]],
                    d["examples"] + [{"owner": "held", "dependencies": []}]]
        for examples in variants:
            bad = copy.deepcopy(d)
            bad["examples"] = examples
            with patch("jevselector.bayes.Counter", side_effect=AssertionError("counted too early")):
                with self.assertRaises(ValueError):
                    fit_bayes(s, bad)

    def test_inconsistent_labels_and_input_identity(self):
        s, d = inputs()
        bad = copy.deepcopy(d)
        bad["premises"][0]["typeHash"] = 99
        with self.assertRaisesRegex(ValueError, "signature"):
            fit_bayes(s, bad)
        bad = copy.deepcopy(d)
        bad["premises"].append(bad["premises"][0])
        with self.assertRaisesRegex(ValueError, "duplicate"):
            fit_bayes(s, bad)
        bad = copy.deepcopy(d)
        bad["statementArtifactId"] = "different"
        with self.assertRaisesRegex(ValueError, "artifact"):
            fit_bayes(s, bad)
        bad = copy.deepcopy(d)
        bad["examples"][0]["dependencies"].append("unknown")
        with self.assertRaisesRegex(ValueError, "labels"):
            fit_bayes(s, bad)

    def test_eligibility_features_and_parameters(self):
        s, d = inputs()
        for kwargs in [{"signature_prior": -1}, {"signature_prior": math.inf},
                       {"observed_weight": 0}, {"observed_weight": math.nan},
                       {"missing_weight": 1}, {"missing_weight": -math.inf},
                       {"max_features": -1}, {"max_features": True}]:
            with self.assertRaises(ValueError):
                fit_bayes(s, d, **kwargs)
        bad = copy.deepcopy(s)
        bad["eligible"].append("held")
        with self.assertRaisesRegex(ValueError, "eligibility"):
            fit_bayes(bad, d)
        bad = copy.deepcopy(s)
        bad["declarations"][0]["symbols"] = [7]
        with self.assertRaisesRegex(ValueError, "features"):
            fit_bayes(bad, d)

    def test_pruning_preserves_label_support_and_strongest_deltas(self):
        s, d = inputs()
        h, full = fit_bayes(s, d, max_features=0)
        hp, pruned = fit_bayes(s, d, max_features=1)
        self.assertEqual(h["symbols"], hp["symbols"])
        for a, b in zip(full, pruned):
            self.assertEqual(a["name"], b["name"])
            self.assertEqual(a["logPrior"], b["logPrior"])
            self.assertEqual(a["features"][:1], b["features"])

    def test_deterministic_fitting_and_empty_features(self):
        s, d = inputs()
        expected = fit_bayes(s, d)
        s["declarations"].reverse()
        s["eligible"].reverse()
        d["examples"].reverse()
        d["premises"].reverse()
        self.assertEqual(fit_bayes(s, d), expected)
        for row in s["declarations"]:
            row["symbols"] = []
        header, premises = fit_bayes(s, d)
        self.assertEqual(header["symbols"], [])
        self.assertTrue(all(not p["features"] for p in premises))
        self.assertEqual(header["featureEdges"], 0)

    def test_unused_or_self_dependency_labels_rejected(self):
        s, d = inputs()
        bad = copy.deepcopy(d)
        bad["premises"].append({"name": "unused", "typeHash": 9})
        with self.assertRaisesRegex(ValueError, "unused"):
            fit_bayes(s, bad)
        bad = copy.deepcopy(d)
        bad["examples"][2]["dependencies"] = ["lemma"]
        with self.assertRaisesRegex(ValueError, "labels"):
            fit_bayes(s, bad)

    def test_empty_training_library_and_input_immutability(self):
        s, d = inputs()
        before = copy.deepcopy((s, d))
        fit_bayes(s, d)
        self.assertEqual((s, d), before)
        s["eligible"] = []
        d["examples"], d["premises"] = [], []
        header, premises = fit_bayes(s, d)
        self.assertEqual(premises, [])
        self.assertEqual(header["exampleOwners"], [])
        self.assertEqual(header["symbols"], [])
        self.assertEqual(header["premiseCount"], 0)


if __name__ == "__main__":
    unittest.main()
