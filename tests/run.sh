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
lake env lean SineQuaNonTests.lean

python -m jevselector profile --modules SelectorFixture --index "$scratch/prepared/index.json" --samples 3 --repeats 2 --output "$scratch/profile" "$@"
