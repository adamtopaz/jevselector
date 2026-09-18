# Contributing

Use Lean 4.33.0 and Python 3.10+. Run `bash tests/run.sh` in a bounded job;
on non-systemd machines use `--external-memory-limit` with a real container/job
limit. Keep the complete process tree below 32 GB; 24 GB with swap disabled is
the development default. Never check in API credentials, bulk artifacts, or
machine-specific dependency paths.

New preparation recipes must expose their inputs, exclusions before fitting,
versioned provenance, and an ordinary Lean selector. Tests must cover holdouts,
future-premise availability, caller filters, and incompatible artifacts. Measure
CPU preparation/query cost and matched JevHammer proof coverage before claiming
an improvement. Keep final evaluation data separate from development choices.

Contributions are under Apache-2.0, like this repository.
