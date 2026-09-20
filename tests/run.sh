#!/usr/bin/env bash
set -euo pipefail
# Put this script in a bounded container/job, or a systemd scope on Linux.
python -m unittest discover -s tests -v
scratch=$(mktemp -d)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$scratch"; else echo "Test evidence retained: $scratch" >&2; fi' EXIT
python -m jevselector prepare --modules SelectorFixture --exclude tests/holdout.json --output "$scratch/prepared" "$@"
python -m jevselector verify "$scratch/prepared"
JEVSELECTOR_TEST_INDEX="$scratch/prepared/index.json" lake env lean JevSelectorTests.lean
python - "$scratch/prepared/index.json" "$scratch/legacy-index.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
for key in ["publicConstants", "candidateOnly"]:
    value.pop(key, None)
json.dump(value, open(sys.argv[2], "w"))
PY
JEVSELECTOR_TEST_INDEX="$scratch/legacy-index.json" lake env lean JevSelectorTests.lean
JEVSELECTOR_TEST_INDEX="$scratch/prepared/index.json" lake env lean EnsembleTests.lean
python - <<'PY'
import os, signal, subprocess
job = subprocess.Popen(["lake", "env", "lean", "AsyncFusionTests.lean"], start_new_session=True)
try:
    status = job.wait(timeout=30)
except subprocess.TimeoutExpired:
    os.killpg(job.pid, signal.SIGKILL)
    job.wait()
    raise
if status:
    raise SystemExit(status)
PY
python -m jevselector dependencies --modules SelectorFixture --index "$scratch/prepared/index.json" --output "$scratch/dependencies" "$@"
python -m jevselector verify "$scratch/dependencies"
JEVSELECTOR_TEST_INDEX="$scratch/prepared/index.json" JEVSELECTOR_TEST_DEPENDENCIES="$scratch/dependencies/dependencies.json" lake env lean DependencyTests.lean
python - "$scratch/dependencies/dependencies.json" "$scratch/legacy-dependencies.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
value.pop("publicLabels", None)
json.dump(value, open(sys.argv[2], "w"))
PY
JEVSELECTOR_TEST_INDEX="$scratch/legacy-index.json" JEVSELECTOR_TEST_DEPENDENCIES="$scratch/legacy-dependencies.json" lake env lean DependencyTests.lean
python -m jevselector usage --index "$scratch/prepared/index.json" --dependencies "$scratch/dependencies/dependencies.json" --output "$scratch/usage" "$@"
python -m jevselector verify "$scratch/usage"
lake build JevSelector.Usage
JEVSELECTOR_TEST_INDEX="$scratch/prepared/index.json" JEVSELECTOR_TEST_USAGE="$scratch/usage/usage.json" lake env lean UsageTests.lean
python -m jevselector bayes --index "$scratch/prepared/index.json" --dependencies "$scratch/dependencies/dependencies.json" --max-features 0 --output "$scratch/bayes" "$@"
python -m jevselector verify "$scratch/bayes"
python tests/bayes_reference.py "$scratch/prepared/index.json" "$scratch/dependencies/dependencies.json" "$scratch/bayes/bayes.jsonl" "$scratch/bayes-reference.json"
lake build JevSelector.Bayes
JEVSELECTOR_TEST_INDEX="$scratch/prepared/index.json" JEVSELECTOR_TEST_BAYES="$scratch/bayes/bayes.jsonl" JEVSELECTOR_TEST_BAYES_REFERENCE="$scratch/bayes-reference.json" python - <<'PY'
import os, signal, subprocess
job = subprocess.Popen(["lake", "env", "lean", "BayesTests.lean"], start_new_session=True)
try:
    status = job.wait(timeout=30)
except subprocess.TimeoutExpired:
    os.killpg(job.pid, signal.SIGKILL)
    job.wait()
    raise
if status:
    raise SystemExit(status)
PY
python -m jevselector prepare --modules ModernFixture --exclude tests/modern-holdout.json --output "$scratch/modern" "$@"
python -m jevselector dependencies --modules ModernFixture --index "$scratch/modern/index.json" --output "$scratch/modern-dependencies" "$@"
python - "$scratch/modern-dependencies/dependencies.json" <<'PY'
import json, sys
model = json.load(open(sys.argv[1]))
assert [row["owner"] for row in model["examples"]] == ["ModernFixture.keep"]
assert [row["name"] for row in model["premises"]] == ["Nat.add_zero"]
PY
lake env lean SineQuaNonTests.lean
lake build JevSelector.Closing
lake env lean ClosingTests.lean
lake build JevSelector.Structural
lake env lean StructuralTests.lean
lake env lean RewriteTests.lean

python -m jevselector prepare --modules CatalogFixture --exclude tests/catalog-holdout.json --catalog public-constants --output "$scratch/catalog" "$@"
python -m jevselector dependencies --modules CatalogFixture --index "$scratch/catalog/index.json" --labels public-constants --output "$scratch/catalog-dependencies" "$@"
JEVSELECTOR_TEST_CATALOG="$scratch/catalog/index.json" JEVSELECTOR_TEST_CATALOG_DEPS="$scratch/catalog-dependencies/dependencies.json" lake env lean CatalogTests.lean
python - "$scratch/catalog/index.json" "$scratch/corrupt-owner-index.json" <<'PY'
import json, sys
value = json.load(open(sys.argv[1]))
name = "CatalogFixture.definitionProof"
value["candidateOnly"].remove(name)
value["eligible"].append(name)
json.dump(value, open(sys.argv[2], "w"))
PY
if python -m jevselector dependencies --modules CatalogFixture --index "$scratch/corrupt-owner-index.json" --output "$scratch/rejected-definition-owner" "$@"; then
  echo "Dependency extraction accepted a non-theorem proof owner" >&2
  exit 1
fi
rg -q 'not an original theorem' "$scratch/rejected-definition-owner/extract.log"

python -m jevselector profile --modules SelectorFixture --index "$scratch/prepared/index.json" --samples 3 --repeats 2 --output "$scratch/profile" "$@"
for method in structural structural-target rewrites rewrites-target structural-rewrites structural-rewrites-target; do
  python -m jevselector profile --modules SelectorFixture --index "$scratch/prepared/index.json" --method "$method" --samples 3 --repeats 2 --output "$scratch/profile-$method" "$@"
done
for method in neighbors proof-hybrid; do
  python -m jevselector profile --modules SelectorFixture --index "$scratch/prepared/index.json" --dependencies "$scratch/dependencies/dependencies.json" --method "$method" --samples 3 --repeats 2 --output "$scratch/profile-$method" "$@"
done
python -m jevselector profile --modules SelectorFixture --index "$scratch/prepared/index.json" --usage "$scratch/usage/usage.json" --method usage --samples 3 --repeats 2 --output "$scratch/profile-usage" "$@"
for method in bayes bayes-target bayes-structural-target; do
  python -m jevselector profile --modules SelectorFixture --index "$scratch/prepared/index.json" --bayes "$scratch/bayes/bayes.jsonl" --method "$method" --samples 3 --repeats 2 --output "$scratch/profile-$method" "$@"
done
