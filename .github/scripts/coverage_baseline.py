"""Fetch an authoritative passing Aura coverage baseline from green main CI."""

from __future__ import annotations

import argparse
from collections.abc import Sequence
from datetime import datetime
from pathlib import Path
import re
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
from typing import Protocol

from coverage_inventory import JsonValue, decode_json


class Executor(Protocol):
    def execute(self: Executor, command: tuple[str, ...]) -> str: ...


class SubprocessExecutor:
    def execute(self: SubprocessExecutor, command: tuple[str, ...]) -> str:
        result = subprocess.run(command, capture_output=True, text=True, timeout=300)
        if result.returncode != 0:
            raise ValueError(f"Baseline command failed with exit {result.returncode}: {(result.stderr or result.stdout).strip()}")
        return result.stdout


def fetch_baseline(
    repo: str,
    output: Path,
    seed: Path,
    executor: Executor | None = None,
) -> None:
    output.unlink(missing_ok=True)
    executor = executor or SubprocessExecutor()
    runs = decode_json(executor.execute(("gh", "run", "list", "--repo", repo, "--workflow", "CI", "--branch", "main", "--event", "push", "--status", "completed", "--limit", "100", "--json", "conclusion,databaseId,headSha,event,createdAt,workflowName")))
    if not isinstance(runs, list) or not runs:
        raise ValueError("No fully green main push CI run exists")
    candidates = [fields for run in runs if (fields := _object(run, "CI run")).get("conclusion") == "success" and fields.get("event") == "push" and fields.get("workflowName") == "CI"]
    if not candidates:
        raise ValueError("No fully green main push CI run exists")
    for candidate in candidates:
        identifier, revision = candidate.get("databaseId"), candidate.get("headSha")
        if not isinstance(identifier, int) or isinstance(identifier, bool) or identifier <= 0 or not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError("CI run identity is malformed")
    for selected in sorted(candidates, key=_created_at, reverse=True):
        details = _object(decode_json(executor.execute(("gh", "run", "view", str(selected["databaseId"]), "--repo", repo, "--json", "jobs,conclusion,headSha,event"))), "CI run details")
        if details.get("conclusion") != "success" or details.get("event") != "push" or details.get("headSha") != selected["headSha"]:
            raise ValueError("CI run details disagree with the selected successful main push identity")
        if _green_jobs(details):
            break
    else:
        raise ValueError("No fully green main push CI run exists")
    output.parent.mkdir(parents=True, exist_ok=True)
    with TemporaryDirectory(dir=output.parent) as directory:
        staged = Path(directory) / "report.json"
        jobs = details["jobs"]
        if not isinstance(jobs, list):
            raise ValueError("CI run jobs must be a list")
        has_coverage = any(_object(job, "CI job").get("name") == "Coverage" for job in jobs)
        if has_coverage:
            inventory = _object(decode_json(executor.execute(("gh", "api", f"repos/{repo}/actions/runs/{selected['databaseId']}/artifacts"))), "coverage artifact inventory")
            artifacts = inventory.get("artifacts")
            if not isinstance(artifacts, list) or type(inventory.get("total_count")) is not int or inventory.get("total_count") != len(artifacts):
                raise ValueError("coverage artifact inventory is incomplete")
            matching = [artifact for value in artifacts if (artifact := _object(value, "coverage artifact")).get("name") == "coverage-baseline"]
            artifact_id = matching[0].get("id") if len(matching) == 1 else None
            if len(matching) != 1 or matching[0].get("expired") is not False or not isinstance(artifact_id, int) or isinstance(artifact_id, bool) or artifact_id <= 0:
                raise ValueError("Exactly one unexpired coverage-baseline artifact is required for the selected run")
            identity = _object(decode_json(executor.execute(("gh", "api", f"repos/{repo}/actions/runs/{selected['databaseId']}"))), "CI run identity")
            attempt = identity.get("run_attempt")
            if type(identity.get("id")) is not int or identity.get("id") != selected["databaseId"] or identity.get("head_sha") != selected["headSha"] or identity.get("head_branch") != "main" or identity.get("event") != "push" or identity.get("conclusion") != "success" or identity.get("status") != "completed" or not isinstance(attempt, int) or isinstance(attempt, bool) or attempt <= 0:
                raise ValueError("CI run identity does not match the selected fully green main push")
            executor.execute(("gh", "run", "download", str(selected["databaseId"]), "--repo", repo, "--name", "coverage-baseline", "--dir", directory))
            report = _object(decode_json(staged.read_text()), "coverage baseline report")
            collection = _object(report.get("collection"), "coverage baseline report collection")
            toolchain = report.get("toolchain")
            if type(report.get("schema")) is not int or report.get("schema") != 1 or report.get("passed") is not True or collection.get("revision") != selected["headSha"] or collection.get("run") != f"github:{selected['databaseId']}:{attempt}" or not isinstance(toolchain, str) or not toolchain.strip():
                raise ValueError("coverage baseline report does not prove success for the selected run and attempt")
        else:
            if not seed.is_file():
                raise ValueError(f"Missing approved initial baseline at {seed}; review candidate measurements and approve a seed for {selected['headSha']}")
            baseline = _object(decode_json(seed.read_text()), "approved initial baseline")
            toolchain = baseline.get("toolchain")
            if baseline.get("approved") is not True or baseline.get("kind") != "approved-initial-baseline" or baseline.get("passed") is not True or type(baseline.get("schema")) is not int or baseline.get("schema") != 1 or baseline.get("source_revision") != selected.get("headSha") or not isinstance(toolchain, str) or not toolchain.strip():
                raise ValueError("An approved initial baseline matching the latest green main revision is required; review candidate measurements first")
            shutil.copyfile(seed, staged)
        staged.replace(output)


def _object(value: JsonValue, label: str) -> dict[str, JsonValue]:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return value


def _created_at(run: dict[str, JsonValue]) -> datetime:
    value = run.get("createdAt")
    if not isinstance(value, str):
        raise ValueError("CI run timestamp is missing")
    timestamp = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if timestamp.tzinfo is None:
        raise ValueError("CI run timestamp lacks timezone")
    return timestamp


def _green_jobs(details: dict[str, JsonValue]) -> bool:
    jobs = details.get("jobs")
    if not isinstance(jobs, list):
        raise ValueError("CI run jobs must be a list")
    required = {"Unit tests (AuraKit)", "Build app (iOS)", "Build app (macOS)", "Snapshot tests (iOS)"}
    found: set[str] = set()
    for value in jobs:
        job = _object(value, "CI job")
        name = job.get("name")
        if not isinstance(name, str):
            raise ValueError("CI job name is missing")
        if name not in required and name != "Coverage":
            continue
        if name in found or job.get("conclusion") != "success":
            return False
        found.add(name)
    return required.issubset(found)


def main(
    arguments: Sequence[str] | None = None,
    executor: Executor | None = None,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default="fardavide/Aura")
    parser.add_argument("--output", default=Path(".coverage-baseline/report.json"), type=Path)
    parser.add_argument("--seed", default=Path(".github/coverage/baseline.json"), type=Path)
    options = parser.parse_args(list(arguments) if arguments is not None else None)
    repo: object = options.repo
    output: object = options.output
    seed: object = options.seed
    if not isinstance(repo, str) or not isinstance(output, Path) or not isinstance(seed, Path):
        raise ValueError("Baseline fetch arguments are missing")
    try:
        fetch_baseline(repo, output, seed, executor)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Coverage baseline fetch failed: {error}", file=sys.stderr)
        return 1
    print(f"Coverage baseline saved to {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
