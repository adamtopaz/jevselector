"""Aggregate Linux cgroup bounds, with explicit externally managed alternatives."""

import os
from pathlib import Path
import shutil
import sys

DEFAULT_LIMIT = 24_000_000_000
MAX_LIMIT = 32_000_000_000


def cgroup_limits():
    try:
        line = next(x for x in Path("/proc/self/cgroup").read_text().splitlines()
                    if x.startswith("0::"))
        path = Path("/sys/fs/cgroup") / line[3:].lstrip("/")
        found, swaps = [], []
        for directory in [path, *path.parents]:
            if not str(directory).startswith("/sys/fs/cgroup"):
                break
            if not (directory / "memory.max").exists():
                continue
            memory = (directory / "memory.max").read_text().strip()
            swap = (directory / "memory.swap.max").read_text().strip()
            if swap != "max":
                swaps.append(int(swap))
            if memory != "max":
                found.append((int(memory), str(directory)))
        if found:
            limit, directory = min(found)
            return {"memoryMax": limit, "swapMax": str(min(swaps)) if swaps else "max",
                    "cgroup": directory}
    except (OSError, StopIteration, ValueError):
        pass
    return None


def ensure_bounded(args):
    if not 0 < args.memory_limit <= MAX_LIMIT:
        raise ValueError("memory limit must be positive and at most 32,000,000,000 bytes")
    limits = cgroup_limits()
    if limits and limits["memoryMax"] <= args.memory_limit and limits["swapMax"] == "0":
        return {"mode": "cgroup", **limits}
    if args.external_memory_limit:
        return {"mode": "externally-managed", "declaredLimit": args.memory_limit,
                "observedCgroup": limits}
    if not shutil.which("systemd-run"):
        raise ValueError("use a bounded container/job and --external-memory-limit, or Linux systemd")
    if os.environ.get("JEVSELECTOR_SCOPE_ATTEMPTED"):
        raise ValueError("systemd did not establish the required aggregate memory/swap limits")
    os.environ["JEVSELECTOR_SCOPE_ATTEMPTED"] = "1"
    os.execvp("systemd-run", ["systemd-run", "--user", "--scope", "--quiet",
              "-p", f"MemoryMax={args.memory_limit}", "-p", "MemorySwapMax=0", "--",
              sys.executable, "-m", "jevselector", *sys.argv[1:]])


def resource_snapshot():
    limits = cgroup_limits()
    if limits:
        path = Path(limits["cgroup"])
        for name in ["memory.peak", "memory.events"]:
            try:
                limits[name] = (path / name).read_text().strip()
            except OSError:
                pass
    return limits
