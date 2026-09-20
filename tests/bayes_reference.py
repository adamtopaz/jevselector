"""Independent direct-score fixtures for the native streamed model test."""
import json
import math
from pathlib import Path
import sys

statement_path, dependency_path, model_path, output = map(Path, sys.argv[1:])
statements = json.loads(statement_path.read_text())
dependencies = json.loads(dependency_path.read_text())
records = [json.loads(line) for line in model_path.read_text().splitlines()]
header, premises = records[0], records[1:]
types = {p["name"]: set(p["symbols"]) for p in statements["declarations"]}
owners = set(statements["eligible"])
queries = [[], ["NeverSeen.feature"], header["symbols"], header["symbols"] * 2]
queries += [[feature] for feature in header["symbols"]]
result = []
for query in queries:
    features = sorted(set(query))
    scores = []
    for premise in premises:
        name = premise["name"]
        examples = [(types[r["owner"]], 1) for r in dependencies["examples"]
                    if name in r["dependencies"]]
        if name in owners and header["signaturePrior"]:
            examples.append((types[name], header["signaturePrior"]))
        support = sum(weight for _, weight in examples)
        direct = math.log(support)
        for feature in features:
            count = sum(weight for terms, weight in examples if feature in terms)
            direct += math.log(header["observedWeight"] * count / support) if count else header["missingWeight"]
        # The native ranker omits this common contribution, including unknown features.
        scores.append({"name": name, "score": direct - len(features) * header["missingWeight"]})
    scores.sort(key=lambda p: (-p["score"], p["name"]))
    result.append({"features": query, "scores": scores})
output.write_text(json.dumps(result) + "\n")
