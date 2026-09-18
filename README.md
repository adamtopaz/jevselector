# jevselector

Generic offline preparation and fast CPU premise selection for Lean libraries,
intended for use with [JevHammer](https://github.com/adamtopaz/jevhammer) and other
consumers of Lean's standard premise-selector interface.

**Status: design stage.** This repository currently contains planning notes.
There is no selector implementation, installation workflow, or trained artifact yet.

"Training" means preparing reusable artifacts; it need not involve a neural
network. The same preparation pipeline should support any Lean library, with
optional holdouts for evaluation or the full library for production use.
Mathlib and benchmark-specific splits must not be built into the selector.

The objectives are practical full-library preparation, fast CPU queries, and
end-to-end JevHammer coverage at least as good as the strongest historical
pipeline under matched conditions. These are research targets, not achieved
performance claims.

Read the [selector design](notes/design.md) for the preparation contract,
holdout semantics, artifact provenance, runtime interface, and candidate methods.
The [benchmark repository](https://github.com/adamtopaz/jevhammer_benchmark)
contains the shared implementation sequence; benchmarking infrastructure comes
first.

This is intended to be a public reusable library, with portable artifacts,
documented preparation/loading workflows, and small offline fixtures. It must
not depend on private worktrees or local experiment state. JevPilot may be used;
neural models are optional. Local development retains a 32 GB RAM ceiling and a
24 GB zero-swap operational limit for the complete heavy process tree.
