"""Prepare a proof-free sparse index for any Lean library, optionally excluding holdouts."""

import argparse
from collections import Counter
import hashlib
import json
import math
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

from .resources import DEFAULT_LIMIT, ensure_bounded, resource_snapshot


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, separators=(",", ":")) + "\n")


def name(value):
    if not re.fullmatch(r"[^\W\d][\w']*(?:\.[^\W\d][\w']*)*", value, re.UNICODE):
        raise ValueError(f"expected an ordinary Lean module identifier: {value!r}")
    return value


def excluded_by(declaration, owners):
    if declaration in owners:
        return True
    return any(declaration[:i] in owners for i, c in enumerate(declaration) if c == ".")


def fit(corpus, holdout=None):
    """Only eligible statement rows contribute to IDF. Proofs are never inputs."""
    lines = iter(corpus)
    header = next(lines)
    if header.get("kind") != "header":
        raise ValueError("missing extraction header")
    declarations, entries = {}, []
    for row in lines:
        if row["kind"] == "declaration":
            declarations[row["name"]] = row["moduleName"]
        elif row["kind"] == "theorem":
            entries.append({k: v for k, v in row.items() if k != "kind"})
        else:
            raise ValueError("unknown corpus record")
    holdout = holdout or {"schema": 1, "declarations": [], "modules": []}
    if holdout.get("schema") != 1:
        raise ValueError("unsupported holdout schema")
    owners = set(holdout.get("declarations", []))
    modules = holdout.get("modules", [])
    unknown = set(owners) - declarations.keys()
    unknown_modules = set(modules) - set(header["modules"])
    if unknown or unknown_modules:
        raise ValueError(f"unresolved holdouts: declarations={sorted(unknown)}, modules={sorted(unknown_modules)}")
    # Require module exclusions to intersect the exported scope, even for loaded imports.
    if set(modules) - set(declarations.values()):
        raise ValueError("held-out module has no declarations in the exported scope")
    excluded = {n for n, m in declarations.items() if m in modules or excluded_by(n, owners)}
    eligible = [e for e in entries if e["name"] not in excluded]
    df = Counter(s for e in eligible for s in set(e["symbols"]))
    n = len(eligible)
    return {"schema": 1, "leanVersion": header["leanVersion"], "declarations": entries,
            "eligible": sorted(e["name"] for e in eligible), "excluded": sorted(excluded),
            "weights": [{"symbol": s, "weight": 1 + math.log((n + 1) / (count + 1))}
                        for s, count in sorted(df.items())]}


def package_directory(project, manifest, package):
    if package["type"] == "path":
        root = project / package["dir"]
    else:
        # Lake's manifest prints quoted Lean identifiers, but checkout names
        # omit the quoting (e.g. «premise-selection» -> premise-selection).
        directory = package["name"].replace("«", "").replace("»", "")
        root = project / manifest.get("packagesDir", ".lake/packages") / directory
    root = root / (package.get("subDir") or "")
    if not root.is_dir():
        raise ValueError(f"missing dependency source directory: {root}; run lake update")
    return root


def source_snapshot(project):
    files = {}
    for directory, dirs, names in os.walk(project):
        directory = Path(directory)
        dirs[:] = sorted(d for d in dirs if d not in {
            ".lake", ".git", ".venv", "__pycache__", "artifacts", "cache", "runs"}
            and not any((directory / d / marker).exists() for marker in
                        [".jevselector-output", ".jevbench-output"]))
        for item in sorted(names):
            path = directory / item
            if path.suffix == ".lean" or item in {"lakefile.toml", "lakefile.lean", "lake-manifest.json", "lean-toolchain"}:
                files[str(path.relative_to(project))] = sha(path.read_bytes())
    manifest = json.loads((project / "lake-manifest.json").read_text())
    # Git revisions alone do not describe dirty dependency sources.
    dependencies = {}
    for package in manifest["packages"]:
        root = package_directory(project, manifest, package)
        hashes = {}
        for path in sorted(root.rglob("*.lean")):
            relative = path.relative_to(root)
            if ".lake" not in relative.parts and ".git" not in relative.parts:
                hashes[str(relative)] = sha(path.read_bytes())
        dependencies[package["name"]] = {"sourceSha256": sha(json.dumps(hashes, sort_keys=True).encode()),
                                         "files": len(hashes)}
    return {"files": files, "dependencies": dependencies, "manifest": manifest}


def process(command, project, log, env=None, timeout=1800):
    with log.open("w") as output:
        child = subprocess.Popen(command, cwd=project, env=env, stdout=output,
                                 stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = child.wait(timeout=timeout)
        except BaseException:
            os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait()
            raise
    if code:
        raise RuntimeError(f"Lean command failed ({code}); see {log}")


def lean_file(project, source, log, env=None, timeout=1800, options=(), module_name="JevSelectorPreparation"):
    """Use Lake's import/plugin setup even for generated files outside the project."""
    setup_log = log.with_suffix(".setup.log")
    process(["lake", "setup-file", str(source)], project, setup_log, env, timeout)
    lines = [line for line in setup_log.read_text().splitlines() if line.startswith("{")]
    if not lines:
        raise RuntimeError(f"missing Lake module setup; see {setup_log}")
    setup = json.loads(lines[-1])
    setup["name"] = module_name
    for option in options:
        if option.startswith("-D"):
            setup.get("options", {}).pop(option[2:].split("=", 1)[0], None)
    setup_file = log.with_suffix(".setup.json")
    write_json(setup_file, setup)
    process(["lake", "env", "lean", "--setup", str(setup_file), *options, str(source)],
            project, log, env, timeout)


def prepare(args):
    resources = ensure_bounded(args)
    start = time.monotonic()
    code_hash = sha(Path(__file__).read_bytes())
    project, output = args.project.absolute(), args.output.absolute()
    output.mkdir(parents=True, exist_ok=False)
    (output / ".jevselector-output").touch()
    modules = sorted(set(map(name, args.modules)))
    scopes = sorted(set(map(name, args.scope or modules)))
    holdout_bytes = args.exclude.read_bytes() if args.exclude else None
    holdout = json.loads(holdout_bytes) if holdout_bytes is not None else None
    report = {"schema": 1, "status": "running", "resources": {"initial": resources}}
    write_json(output / "report.json", report)
    try:
        process(["lake", "build", "JevSelector", *modules], project, output / "build.log", timeout=args.timeout)
        snapshot = source_snapshot(project)
        source = "import JevSelector.Export\n" + "".join(f"import {m}\n" for m in modules) + "\n#jevselector_export\n"
        (output / "Extract.lean").write_text(source)
        config = output / "export.json"
        write_json(config, {"output": str(output / "corpus.jsonl"), "scopes": scopes})
        env = dict(os.environ, JEVSELECTOR_EXPORT_CONFIG=str(config), LEAN_NUM_THREADS=str(args.threads))
        lean_file(project, output / "Extract.lean", output / "extract.log", env, args.timeout,
                  [f"-j{args.threads}", "-M0", "-DmaxHeartbeats=0"])
        extraction_seconds = time.monotonic() - start
        with (output / "corpus.jsonl").open() as handle:
            artifact = fit((json.loads(line) for line in handle), holdout)
        if not artifact["declarations"]:
            raise ValueError("exported scope contains no public theorems")
        recipe = {"algorithm": "statement-symbol-idf-v1", "modules": modules, "scopes": scopes,
                  "proofInformation": "none", "heldoutStatementStatistics": "excluded",
                  "statementCatalog": "retained; runtime availability and caller filter required"}
        source_hash = sha(json.dumps(snapshot, sort_keys=True).encode())
        if sha(Path(__file__).read_bytes()) != code_hash:
            raise RuntimeError("preparation code changed during extraction; retry from a fixed revision")
        identity = dict(recipe=recipe, sourceSha256=source_hash, preparationCodeSha256=code_hash,
                        holdoutSha256=sha(holdout_bytes) if holdout_bytes is not None else None)
        artifact["provenance"] = dict(identity, artifactId=sha(json.dumps(identity, sort_keys=True).encode()),
                                      mode="holdout" if holdout is not None else "full-library",
                                      holdout=holdout, snapshot=snapshot)
        write_json(output / "index.json", artifact)
        checksum = sha((output / "index.json").read_bytes())
        (output / "index.sha256").write_text(checksum + "  index.json\n")
        report.update(status="complete", indexSha256=checksum, recipe=recipe,
                      declarations=len(artifact["declarations"]), eligible=len(artifact["eligible"]),
                      excluded=len(artifact["excluded"]), symbols=len(artifact["weights"]),
                      artifactBytes=(output / "index.json").stat().st_size,
                      extractionSeconds=extraction_seconds)
        print(f"Prepared {report['declarations']} theorems ({report['eligible']} eligible): {output / 'index.json'}")
    except BaseException as error:
        report.update(status="incomplete", error=str(error))
        raise
    finally:
        report["totalSeconds"] = time.monotonic() - start
        report["resources"]["final"] = resource_snapshot()
        write_json(output / "report.json", report)


def verify(args):
    output = args.directory
    expected = (output / "index.sha256").read_text().split()[0]
    if sha((output / "index.json").read_bytes()) != expected:
        raise ValueError("artifact checksum mismatch")
    print("Artifact SHA-256 verified")


def profile(args):
    resources = ensure_bounded(args)
    project, output = args.project.absolute(), args.output.absolute()
    output.mkdir(parents=True, exist_ok=False)
    (output / ".jevselector-output").touch()
    modules = sorted(set(map(name, args.modules)))
    process(["lake", "build", "JevSelector.Profile", *modules], project, output / "build.log")
    source = "import JevSelector.Profile\n" + "".join(f"import {m}\n" for m in modules) + "\n#jevselector_profile\n"
    (output / "Profile.lean").write_text(source)
    config = output / "config.json"
    write_json(config, {"index": str(args.index.absolute()), "output": str(output / "queries.json"),
                        "samples": args.samples, "repeats": args.repeats, "method": args.method})
    env = dict(os.environ, JEVSELECTOR_PROFILE_CONFIG=str(config), JEVSELECTOR_TRACE_LOAD="1")
    lean_file(project, output / "Profile.lean", output / "profile.log", env, args.timeout,
              [f"-j{args.threads}", "-M0", "-DmaxHeartbeats=0"], "JevSelectorProfile")
    report = json.loads((output / "queries.json").read_text())
    timings = sorted(r["elapsedNanos"] / 1e6 for r in report["queries"])
    if not timings:
        raise ValueError("no available profile statements")
    write_json(output / "summary.json", {"schema": 1, "kind": "query-latency-only",
               "method": args.method,
               "loadMs": report["loadMs"], "queries": len(timings),
               "medianMs": timings[len(timings) // 2], "p95Ms": timings[min(len(timings)-1, int(len(timings)*.95))],
               "meanMs": sum(timings)/len(timings), "resources": {"initial": resources, "final": resource_snapshot()}})
    print((output / "summary.json").read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("--project", type=Path, default=Path.cwd())
    p.add_argument("--modules", nargs="+", required=True)
    p.add_argument("--scope", action="append", default=[], help="module prefix to include; default: root modules")
    p.add_argument("--exclude", type=Path)
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--threads", type=int, default=2)
    p.add_argument("--timeout", type=int, default=1800)
    p.add_argument("--memory-limit", type=int, default=DEFAULT_LIMIT)
    p.add_argument("--external-memory-limit", action="store_true")
    p = sub.add_parser("profile")
    p.add_argument("--project", type=Path, default=Path.cwd())
    p.add_argument("--modules", nargs="+", required=True)
    p.add_argument("--index", type=Path, required=True)
    p.add_argument("--method", choices=["sparse", "target", "ensemble"], default="sparse")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--samples", type=int, default=32)
    p.add_argument("--repeats", type=int, default=3)
    p.add_argument("--threads", type=int, default=2)
    p.add_argument("--timeout", type=int, default=1800)
    p.add_argument("--memory-limit", type=int, default=DEFAULT_LIMIT)
    p.add_argument("--external-memory-limit", action="store_true")
    sub.add_parser("verify").add_argument("directory", type=Path)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            prepare(args)
        elif args.command == "profile":
            if args.samples <= 0 or args.repeats <= 0:
                raise ValueError("samples and repeats must be positive")
            profile(args)
        else:
            verify(args)
    except (ValueError, RuntimeError, OSError, subprocess.SubprocessError) as error:
        print(f"jevselector: {error}", file=sys.stderr)
        raise SystemExit(1)
