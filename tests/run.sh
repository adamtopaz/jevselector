#!/usr/bin/env bash
set -euo pipefail
# Put this script in a bounded container/job, or a systemd scope on Linux.
python -m unittest discover -s tests -v
scratch=$(mktemp -d)
trap 'status=$?; if [ "$status" -eq 0 ]; then rm -rf "$scratch"; else echo "Test evidence retained: $scratch" >&2; fi' EXIT
python -m jevselector prepare --modules SelectorFixture --exclude tests/holdout.json --output "$scratch/prepared" "$@"
python -m jevselector verify "$scratch/prepared"
JEVSELECTOR_TEST_INDEX="$scratch/prepared/index.json" lake env lean JevSelectorTests.lean
JEVSELECTOR_TEST_INDEX="$scratch/prepared/index.json" lake env lean EnsembleTests.lean
python -m jevselector dependencies --modules SelectorFixture --index "$scratch/prepared/index.json" --output "$scratch/dependencies" "$@"
python -m jevselector verify "$scratch/dependencies"
JEVSELECTOR_TEST_INDEX="$scratch/prepared/index.json" JEVSELECTOR_TEST_DEPENDENCIES="$scratch/dependencies/dependencies.json" lake env lean DependencyTests.lean
python -m jevselector usage --index "$scratch/prepared/index.json" --dependencies "$scratch/dependencies/dependencies.json" --output "$scratch/usage" "$@"
python -m jevselector verify "$scratch/usage"
lake build JevSelector.Usage
JEVSELECTOR_TEST_INDEX="$scratch/prepared/index.json" JEVSELECTOR_TEST_USAGE="$scratch/usage/usage.json" lake env lean UsageTests.lean
python -m jevselector prepare --modules ModernFixture --exclude tests/modern-holdout.json --output "$scratch/modern" "$@"
python -m jevselector dependencies --modules ModernFixture --index "$scratch/modern/index.json" --output "$scratch/modern-dependencies" "$@"
python - "$scratch/modern-dependencies/dependencies.json" <<'PY'
import json, sys
model = json.load(open(sys.argv[1]))
assert [row["owner"] for row in model["examples"]] == ["ModernFixture.keep"]
assert [row["name"] for row in model["premises"]] == ["Nat.add_zero"]
PY
lake env lean SineQuaNonTests.lean

python -m jevselector profile --modules SelectorFixture --index "$scratch/prepared/index.json" --samples 3 --repeats 2 --output "$scratch/profile" "$@"
for method in neighbors proof-hybrid; do
  python -m jevselector profile --modules SelectorFixture --index "$scratch/prepared/index.json" --dependencies "$scratch/dependencies/dependencies.json" --method "$method" --samples 3 --repeats 2 --output "$scratch/profile-$method" "$@"
done
python -m jevselector profile --modules SelectorFixture --index "$scratch/prepared/index.json" --usage "$scratch/usage/usage.json" --method usage --samples 3 --repeats 2 --output "$scratch/profile-usage" "$@"
