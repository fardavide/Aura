"""Measure Aura production sources and enforce six exact coverage ratchets."""

from dataclasses import asdict, dataclass, field
from enum import Enum
from pathlib import Path
from collections.abc import Mapping
from typing import TypeAlias
from html import escape
import json
from coverage_inventory import decode_json


Json: TypeAlias = None | bool | int | float | str | list["Json"] | dict[str, "Json"]


class Scope(str, Enum):
    APP_HOSTED = "aura-production-ios-v1"
    PACKAGE = "aurakit-production-host-v1"
    TOTAL = "aura-production-host-first-union-v1"


@dataclass(frozen=True)
class Counter:
    covered: int
    count: int

    def __post_init__(self: "Counter") -> None:
        if type(self.covered) is not int or type(self.count) is not int or not 0 <= self.covered <= self.count or self.count <= 0:
            raise ValueError("Invalid coverage counter")


def check_ratio(baseline: Counter, current: Counter) -> bool:
    return current.covered * baseline.count >= baseline.covered * current.count


@dataclass(frozen=True)
class FileCounters:
    lines: Counter
    regions: Counter


@dataclass(frozen=True)
class Measurement:
    files: tuple[str, ...]
    lines: Counter
    regions: Counter
    scope: Scope
    file_counters: Mapping[str, FileCounters] = field(default_factory=dict)
    unmapped_files: tuple[str, ...] = ()


def read_baseline(path: Path, toolchain: str) -> Mapping[Scope, Measurement]:
    baseline = decode_json(path.read_text())
    if not isinstance(baseline, dict) or baseline.get("toolchain") != toolchain:
        raise ValueError("Coverage baseline toolchain does not match")
    if type(baseline.get("schema")) is not int or baseline.get("schema") != 1 or baseline.get("passed") is not True:
        raise ValueError("Coverage baseline must be a successful schema-1 report")
    values = baseline.get("measurements")
    if not isinstance(values, dict) or set(values) != {scope.value for scope in Scope}:
        raise ValueError("Coverage baseline requires all three categories")
    measurements: dict[Scope, Measurement] = {}
    for scope in Scope:
        value = values[scope.value]
        if not isinstance(value, dict):
            raise ValueError("Invalid coverage baseline measurement")
        files = value.get("files")
        if not isinstance(files, list) or not files or any(not isinstance(file, str) or not file for file in files) or len(set(files)) != len(files):
            raise ValueError("Invalid coverage baseline source inventory")
        counters: dict[str, Counter] = {}
        for name in ("lines", "regions"):
            counter = value.get(name)
            if not isinstance(counter, dict) or set(counter) != {"covered", "count"}:
                raise ValueError("Invalid coverage baseline counter")
            covered, count = counter["covered"], counter["count"]
            if type(covered) is not int or type(count) is not int:
                raise ValueError("Invalid coverage baseline counter")
            counters[name] = Counter(covered=covered, count=count)
        measurements[scope] = Measurement(
            files=tuple(files), lines=counters["lines"], regions=counters["regions"], scope=scope,
        )
    return measurements


def check_ratchets(
    baseline: Mapping[Scope, Measurement],
    current: Mapping[Scope, Measurement],
) -> tuple[bool, ...]:
    if set(baseline) != set(Scope) or set(current) != set(Scope):
        raise ValueError("Coverage requires all three categories in current and baseline")
    if any(values[scope].scope != scope for values in (baseline, current) for scope in Scope):
        raise ValueError("Coverage measurement scope disagrees with category")
    return tuple(
        check_ratio(baseline=getattr(baseline[scope], counter), current=getattr(current[scope], counter))
        for scope in Scope
        for counter in ("lines", "regions")
    )


def build_report(
    baseline: Mapping[Scope, Measurement],
    current: Mapping[Scope, Measurement],
    toolchain: str,
) -> dict[str, Json]:
    verdicts = check_ratchets(baseline=baseline, current=current)
    ratchets: list[Json] = []
    for index, (scope, metric) in enumerate((scope, metric) for scope in Scope for metric in ("lines", "regions")):
        ratchets.append({
            "baseline": asdict(getattr(baseline[scope], metric)),
            "current": asdict(getattr(current[scope], metric)),
            "metric": metric,
            "passed": verdicts[index],
            "scope": scope.value,
        })
    return {
        "measurements": {
            scope.value: {
                **({"file_counters": {name: asdict(counters) for name, counters in current[scope].file_counters.items()}} if current[scope].file_counters else {}),
                "files": list(current[scope].files),
                "lines": asdict(current[scope].lines),
                "regions": asdict(current[scope].regions),
                **({"unmapped_files": list(current[scope].unmapped_files)} if current[scope].unmapped_files else {}),
            } for scope in Scope
        },
        "passed": all(verdicts),
        "ratchets": ratchets,
        "schema": 1,
        "toolchain": toolchain,
    }


def render_report(report: dict[str, Json], path: Path) -> None:
    ratchets = report.get("ratchets")
    measurements = report.get("measurements")
    if not isinstance(ratchets, list) or len(ratchets) != 6 or not isinstance(measurements, dict) or type(report.get("passed")) is not bool:
        raise ValueError("HTML report requires all six evaluated coverage verdicts")
    rows: list[str] = []
    for value in ratchets:
        if not isinstance(value, dict):
            raise ValueError("Invalid coverage ratchet report")
        baseline, current = value.get("baseline"), value.get("current")
        if not isinstance(baseline, dict) or not isinstance(current, dict):
            raise ValueError("Missing coverage ratchet counts")
        cells = (
            str(value.get("scope")), str(value.get("metric")),
            f"{baseline.get('covered')}/{baseline.get('count')}",
            f"{current.get('covered')}/{current.get('count')}",
            "PASSED" if value.get("passed") is True else "FAILED",
        )
        rows.append("<tr>" + "".join(f"<td>{escape(cell)}</td>" for cell in cells) + "</tr>")
    details: list[str] = []
    for scope, value in measurements.items():
        if not isinstance(value, dict) or not isinstance(value.get("files"), list):
            raise ValueError("Missing coverage measurement source files")
        details.append(f"<details><summary>{escape(scope)} source measurements</summary><pre>{escape(json.dumps(value, indent=2, sort_keys=True))}</pre></details>")
    status = "PASSED" if report["passed"] else "FAILED"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "<!doctype html><html lang='en'><meta charset='utf-8'><title>Aura coverage</title>"
        "<style>body{font:16px system-ui;margin:40px;max-width:1300px;color:#222;background:#fafafa}"
        "table{border-collapse:collapse;width:100%}td,th{padding:12px;text-align:left;border-bottom:1px solid #ccc}"
        "pre{white-space:pre-wrap;overflow-wrap:anywhere}details{margin:20px 0}</style>"
        f"<h1>Aura coverage: {status}</h1><p>Each line and region ratchet uses exact integer ratios, with zero tolerance.</p>"
        "<p>Total merges raw counters with package mappings first, then iOS mappings, matching Granita. "
        "LLVM retains the first mapping for an overlapping function and source file; alternative iOS regions "
        "remain measured and independently gated in the app-hosted iOS category.</p>"
        "<table><thead><tr><th>Scope</th><th>Metric</th><th>Baseline</th><th>Current</th><th>Verdict</th></tr></thead>"
        f"<tbody>{''.join(rows)}</tbody></table>{''.join(details)}"
        f"<details><summary>Toolchain</summary><pre>{escape(str(report.get('toolchain')))}</pre></details></html>\n"
    )


def measure_export(
    export: Json,
    root: str,
    scope: Scope,
) -> Measurement:
    if not isinstance(export, dict) or not isinstance(export.get("data"), list):
        raise ValueError("Invalid LLVM coverage export")
    line_covered = line_count = region_covered = region_count = 0
    included: set[str] = set()
    file_counters: dict[str, FileCounters] = {}
    for unit in export["data"]:
        if not isinstance(unit, dict) or not isinstance(unit.get("files"), list):
            raise ValueError("Invalid LLVM coverage file inventory")
        for file in unit["files"]:
            if not isinstance(file, dict) or not isinstance(file.get("filename"), str):
                raise ValueError("Invalid LLVM coverage source path")
            path = Path(file["filename"])
            if ".." in path.parts or not path.is_absolute():
                raise ValueError(f"Invalid coverage source path: {path}")
            if not path.is_relative_to(Path(root)):
                continue
            relative = path.relative_to(Path(root)).as_posix()
            prefixes = ("AuraKit/Sources/",) if scope == Scope.PACKAGE else ("AuraKit/Sources/", "Aura/")
            if not relative.startswith(prefixes) or not relative.endswith(".swift"):
                continue
            if relative in included:
                raise ValueError(f"Duplicate coverage file: {relative}")
            summary = file.get("summary")
            if not isinstance(summary, dict):
                raise ValueError(f"Missing coverage summary: {relative}")
            counters: dict[str, Counter] = {}
            for key in ("lines", "regions"):
                counter = summary.get(key)
                if not isinstance(counter, dict):
                    raise ValueError(f"Missing coverage counter: {relative}")
                count, covered = counter.get("count"), counter.get("covered")
                if type(count) is not int or type(covered) is not int or not 0 <= covered <= count:
                    raise ValueError(f"Invalid coverage counter: {relative}")
                counters[key] = Counter(covered=covered, count=count)
                if key == "lines":
                    line_count += count
                    line_covered += covered
                else:
                    region_count += count
                    region_covered += covered
            included.add(relative)
            file_counters[relative] = FileCounters(lines=counters["lines"], regions=counters["regions"])
    return Measurement(
        files=tuple(sorted(included)),
        lines=Counter(covered=line_covered, count=line_count),
        regions=Counter(covered=region_covered, count=region_count),
        scope=scope,
        file_counters=file_counters,
    )
