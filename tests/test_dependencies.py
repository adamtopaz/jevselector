import copy
import unittest

from jevselector.dependencies import fit_dependencies


def inputs():
    index = {"leanVersion": "test", "eligible": ["Example.a", "Example.b"],
             "excluded": ["Example.held", "Example.held.helper"],
             "provenance": {"artifactId": "excluded-index"}}
    rows = [
        {"kind": "dependency-header", "leanVersion": "test", "statementArtifactId": "excluded-index"},
        {"kind": "proof", "owner": "Example.a", "dependencies": [{"name": "Example.lemma", "typeHash": 1}]},
        {"kind": "proof", "owner": "Example.b", "dependencies": []},
    ]
    return index, rows


class Dependencies(unittest.TestCase):
    def test_empty_proofs_are_examples(self):
        index, rows = inputs()
        model = fit_dependencies(rows, index)
        self.assertEqual(len(model["examples"]), 2)
        self.assertGreater(model["premises"][0]["weight"], 1)

    def test_excluded_owner_and_helper_never_fit(self):
        index, rows = inputs()
        for name in index["excluded"]:
            poisoned = copy.deepcopy(rows)
            poisoned.append({"kind": "proof", "owner": name,
                             "dependencies": [{"name": "Leaked.secret", "typeHash": 4}]})
            with self.assertRaisesRegex(ValueError, "ineligible"):
                fit_dependencies(poisoned, index)

    def test_missing_and_duplicate_examples(self):
        index, rows = inputs()
        with self.assertRaisesRegex(ValueError, "incomplete"):
            fit_dependencies(rows[:-1], index)
        with self.assertRaisesRegex(ValueError, "duplicate"):
            fit_dependencies(rows + [rows[-1]], index)

    def test_distinct_statement_index_rejected(self):
        index, rows = inputs()
        rows[0]["statementArtifactId"] = "full-library-index"
        with self.assertRaisesRegex(ValueError, "does not match"):
            fit_dependencies(rows, index)

    def test_labels_do_not_expose_held_out_proof(self):
        index, rows = inputs()
        # An earlier held-out theorem can be a premise in another eligible proof.
        # It still does not become an example whose own proof is read or fitted.
        rows[1]["dependencies"] = [{"name": "Example.held", "typeHash": 7}]
        model = fit_dependencies(rows, index)
        self.assertEqual(model["premises"][0]["name"], "Example.held")
        self.assertNotIn("Example.held", [row["owner"] for row in model["examples"]])

    def test_inconsistent_and_duplicate_labels(self):
        index, rows = inputs()
        rows[2]["dependencies"] = [{"name": "Example.lemma", "typeHash": 8}]
        with self.assertRaisesRegex(ValueError, "inconsistent"):
            fit_dependencies(rows, index)
        rows[2]["dependencies"] = 2 * [{"name": "Example.lemma", "typeHash": 1}]
        with self.assertRaisesRegex(ValueError, "duplicate"):
            fit_dependencies(rows, index)


if __name__ == "__main__":
    unittest.main()
