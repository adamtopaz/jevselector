"""Sparse, CPU-fitted language models of the statements using each premise."""

from collections import Counter, defaultdict
import math


def fit_usage(statements, dependencies, *, smoothing_mass=20.0, max_features=64):
    """Fit only after validating every linked example, label, and exclusion."""
    if not math.isfinite(smoothing_mass) or smoothing_mass <= 0 or max_features < 0:
        raise ValueError("usage smoothing must be positive and feature limit nonnegative")
    identity = statements["provenance"]["artifactId"]
    if (statements.get("schema") != 1 or dependencies.get("schema") != 1
            or dependencies["leanVersion"] != statements["leanVersion"]
            or dependencies["statementArtifactId"] != identity):
        raise ValueError("usage inputs do not share a statement artifact")
    eligible = set(statements["eligible"])
    declarations = {row["name"]: row for row in statements["declarations"]}
    if (len(eligible) != len(statements["eligible"])
            or len(declarations) != len(statements["declarations"])
            or not eligible <= declarations.keys()
            or eligible & set(statements["excluded"])):
        raise ValueError("invalid statement eligibility")
    labels = {row["name"]: row for row in dependencies["premises"]}
    if len(labels) != len(dependencies["premises"]):
        raise ValueError("duplicate premise label")
    seen = set()
    for row in dependencies["examples"]:
        owner, names = row["owner"], row["dependencies"]
        if owner not in eligible or owner in seen:
            raise ValueError("duplicate or ineligible usage example")
        seen.add(owner)
        if len(set(names)) != len(names) or not set(names) <= labels.keys() or owner in names:
            raise ValueError("invalid usage labels")
    if seen != eligible:
        raise ValueError("incomplete eligible usage example set")
    # No proof-sensitive statistics are computed before all admission checks.
    background = Counter()
    for owner in eligible:
        background.update(set(declarations[owner]["symbols"]))
    token_count = sum(background.values())
    counts, support = defaultdict(Counter), Counter()
    for row in dependencies["examples"]:
        features = set(declarations[row["owner"]]["symbols"])
        for label in row["dependencies"]:
            counts[label].update(features)
            support[label] += 1
    if set(support) != set(labels):
        raise ValueError("unused dependency labels")
    vocabulary = sorted(background)
    feature_ids = {feature: i for i, feature in enumerate(vocabulary)}
    premises = []
    for name in sorted(labels):
        count = counts[name]
        weighted = [(feature, math.log1p(n * token_count / (smoothing_mass * background[feature])))
                    for feature, n in count.items()]
        weighted.sort(key=lambda item: (-item[1], item[0]))
        if max_features:
            weighted = weighted[:max_features]
        premises.append({"name": name, "typeHash": labels[name]["typeHash"],
                         "logPrior": math.log((support[name] + 1) / (len(eligible) + 2)),
                         "logNormalizer": math.log1p(sum(count.values()) / smoothing_mass),
                         "features": [{"symbol": feature_ids[feature], "weight": weight}
                                      for feature, weight in weighted]})
    return {"schema": 1, "leanVersion": statements["leanVersion"],
            "statementArtifactId": identity, "exampleOwners": sorted(eligible),
            "smoothingMass": smoothing_mass, "maxFeatures": max_features,
            "symbols": vocabulary, "premises": premises}
