"""Fit a direct proof-dependency companion to an already excluded statement index."""

from collections import Counter
import math


def fit_dependencies(records, statements):
    """Reject excluded/missing/duplicate proof examples before counting any labels."""
    records = iter(records)
    header = next(records)
    if (header.get("kind") != "dependency-header"
            or header.get("leanVersion") != statements["leanVersion"]
            or header.get("statementArtifactId") != statements["provenance"]["artifactId"]):
        raise ValueError("dependency export does not match its statement index")
    eligible = set(statements["eligible"])
    seen, examples, premises = set(), [], {}
    for record in records:
        owner = record.get("owner")
        if record.get("kind") != "proof" or owner not in eligible or owner in seen:
            raise ValueError(f"duplicate, ineligible, or malformed proof example: {owner}")
        seen.add(owner)
        dependencies = []
        for premise in record["dependencies"]:
            name, type_hash = premise["name"], premise["typeHash"]
            if name in dependencies or name == owner:
                raise ValueError("duplicate or self-referential dependency label")
            if name in premises and premises[name] != type_hash:
                raise ValueError("inconsistent dependency statement hash")
            premises[name] = type_hash
            dependencies.append(name)
        examples.append({"owner": owner, "dependencies": sorted(dependencies)})
    if seen != eligible:
        raise ValueError("incomplete eligible proof example set")
    # All exclusion/coverage checks precede proof-sensitive statistics.
    frequencies = Counter(name for row in examples for name in row["dependencies"])
    count = len(examples)
    return {
        "schema": 1, "leanVersion": statements["leanVersion"],
        "statementArtifactId": statements["provenance"]["artifactId"],
        "examples": sorted(examples, key=lambda row: row["owner"]),
        "premises": [{"name": name, "typeHash": premises[name],
                      "weight": 1 + math.log((count + 1) / (frequencies[name] + 1))}
                     for name in sorted(premises)],
    }
