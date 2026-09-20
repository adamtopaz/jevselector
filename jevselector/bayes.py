"""CPU-fitted sparse Bayes with signature priors restricted to eligible owners.

The weighting idea follows MaSh (Kuehlwein et al., 2013, section 3.3).
This is a distinct model from the Dirichlet-smoothed usage learner.
"""

from collections import Counter, defaultdict
import math


def _type_hash(row):
    value = row.get("typeHash")
    if type(value) is not int or not 0 <= value < 2**64:
        raise ValueError("invalid statement type hash")
    return value


def _named_rows(rows, description):
    result = {}
    for row in rows:
        name = row.get("name")
        if not isinstance(name, str) or not name or name in result:
            raise ValueError(f"invalid or duplicate {description} name")
        _type_hash(row)
        result[name] = row
    return result


def fit_bayes(statements, dependencies, *, signature_prior=20.0,
              observed_weight=10.0, missing_weight=-15.0, max_features=64):
    """Return a header and label records, suitable for streaming serialization.

    Every input is admitted before accumulating any statistics. Held-out labels
    may be predicted from eligible proofs but never acquire a self example.
    """
    if (not math.isfinite(signature_prior) or not 0 <= signature_prior <= 1e6
            or not math.isfinite(observed_weight) or not 0 < observed_weight <= 1e6
            or not math.isfinite(missing_weight) or not -1e6 <= missing_weight <= 0
            or type(max_features) is not int or max_features < 0):
        raise ValueError("invalid Bayes parameters")
    identity = statements["provenance"]["artifactId"]
    if (statements.get("schema") != 1 or dependencies.get("schema") != 1
            or dependencies["leanVersion"] != statements["leanVersion"]
            or dependencies["statementArtifactId"] != identity):
        raise ValueError("Bayes inputs do not share a statement artifact")
    declarations = _named_rows(statements["declarations"], "statement")
    eligible = set(statements["eligible"])
    if (len(eligible) != len(statements["eligible"])
            or not eligible <= declarations.keys()
            or eligible & set(statements["excluded"])):
        raise ValueError("invalid statement eligibility")
    for row in declarations.values():
        features = row.get("symbols")
        if not isinstance(features, list) or any(not isinstance(f, str) or not f for f in features):
            raise ValueError("invalid statement features")
    labels = _named_rows(dependencies["premises"], "premise label")
    for name, label in labels.items():
        if name in declarations and label["typeHash"] != declarations[name]["typeHash"]:
            raise ValueError("inconsistent label signature")
    seen, used_labels = set(), set()
    for row in dependencies["examples"]:
        owner, names = row["owner"], row["dependencies"]
        if owner not in eligible or owner in seen:
            raise ValueError("duplicate or ineligible Bayes example")
        seen.add(owner)
        if len(set(names)) != len(names) or not set(names) <= labels.keys() or owner in names:
            raise ValueError("invalid Bayes dependency labels")
        used_labels.update(names)
    if seen != eligible:
        raise ValueError("incomplete eligible Bayes example set")
    if used_labels != labels.keys():
        raise ValueError("unused dependency labels")

    # Proof-use counts remain integers until the synthetic prior is added once.
    # This also makes fitting independent of the example and feature order.
    counts, support = defaultdict(Counter), Counter()
    vocabulary = set()
    for row in dependencies["examples"]:
        features = set(declarations[row["owner"]]["symbols"])
        vocabulary.update(features)
        for label in row["dependencies"]:
            counts[label].update(features)
            support[label] += 1
    signature_owners = sorted(eligible) if signature_prior else []
    for owner in signature_owners:
        support[owner] += signature_prior
        for feature in set(declarations[owner]["symbols"]):
            counts[owner][feature] += signature_prior

    symbols = sorted(vocabulary)
    feature_ids = {feature: i for i, feature in enumerate(symbols)}
    premises = []
    for name in sorted(support):
        log_support = math.log(support[name])
        # Drop only the query-wide missing-feature contribution. A query restores
        # it for exact scores or omits it when it only needs the ranking.
        weights = [(feature, math.log(observed_weight) + math.log(count)
                    - log_support - missing_weight)
                   for feature, count in counts.pop(name, {}).items()]
        weights.sort(key=lambda item: (-item[1], item[0]))
        if max_features:
            weights = weights[:max_features]
        source = labels[name] if name in labels else declarations[name]
        premises.append({"name": name, "typeHash": source["typeHash"],
                         "logPrior": log_support,
                         "features": [{"symbol": feature_ids[feature], "weight": weight}
                                      for feature, weight in weights]})
    header = {"schema": 1, "kind": "weighted-sparse-bayes-v1",
              "leanVersion": statements["leanVersion"], "statementArtifactId": identity,
              "exampleOwners": sorted(eligible), "signaturePriorOwners": signature_owners,
              "signaturePrior": signature_prior, "observedWeight": observed_weight,
              "missingWeight": missing_weight, "maxFeatures": max_features,
              "symbols": symbols, "premiseCount": len(premises),
              "featureEdges": sum(len(p["features"]) for p in premises)}
    return header, premises
