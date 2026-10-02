"""Aggregate compatible native coverage artifacts without running tests."""

from __future__ import annotations

import argparse
from dataclasses import asdict, replace
import json
import os
from pathlib import Path
import subprocess
import sys
from typing import Protocol

from coverage_artifacts import CollectionIdentity, ValidatedArtifact, validate_artifact
from coverage_inventory import (
    JsonValue,
    decode_json,
    enumerated_ios_tests,
    IosRuntimeIdentity,
    ios_runtime_identity,
    package_methods,
    verify_ios_tests,
    verify_package_events,
    verify_partition,
)
from coverage_products import source_digest, source_inventory, validate_mapping_inventory, verify_application_reference
from coverage_report import Measurement, Scope, build_report, measure_export, read_baseline, render_report


class Executor(Protocol):
    def execute(self: Executor, command: tuple[str, ...]) -> str: ...


class SubprocessExecutor:
    def execute(self: SubprocessExecutor, command: tuple[str, ...]) -> str:
        result = subprocess.run(command, capture_output=True, text=True, timeout=300)
        if result.stderr:
            raise ValueError(f"LLVM diagnostic: {result.stderr.strip()}")
        if result.returncode != 0:
            raise ValueError(f"LLVM command failed with exit {result.returncode}: {result.stdout.strip()}")
        return result.stdout


def aggregate(
    baseline_path: Path,
    context_path: Path,
    inputs: Path,
    output: Path,
    executor: Executor | None = None,
    ios_shards: int = 2,
    root: Path | None = None,
) -> bool:
    for name in ("report.json", "report.html", "candidate.json"):
        (output / name).unlink(missing_ok=True)
    _collection_suites(inputs, ios_shards)
    common_identity = _identity(
        decode_json(context_path.read_text()), str(root or Path(__file__).resolve().parents[2]),
    )
    baseline = read_baseline(baseline_path, common_identity.toolchain)
    baseline_document = decode_json(baseline_path.read_text())
    if not isinstance(baseline_document, dict) or not isinstance(baseline_document.get("ios_runtime"), dict):
        raise ValueError("Coverage baseline requires the native iOS runtime identity")
    identity, current, runtime = measure_artifacts(
        context_path=context_path,
        executor=executor,
        inputs=inputs,
        ios_shards=ios_shards,
        output=output,
        root=root,
        baseline_runtime=baseline_document["ios_runtime"],
    )
    report = build_report(baseline, current, identity.toolchain)
    report["collection"] = asdict(identity)
    report["ios_runtime"] = asdict(runtime)
    passed = report["passed"]
    if type(passed) is not bool:
        raise ValueError("coverage report verdict must be boolean")
    (output / "report.json").write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    render_report(report, output / "report.html")
    return passed


def main(
    arguments: tuple[str, ...] | None = None,
    executor: Executor | None = None,
    root: Path | None = None,
) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--baseline", type=Path)
    mode.add_argument("--candidate", action="store_true")
    parser.add_argument("--context", required=True, type=Path)
    parser.add_argument("--inputs", required=True, type=Path)
    parser.add_argument("--ios-shards", choices=(1, 2), default=2, type=int)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--application-reference", default=os.environ.get("AURA_COVERAGE_APPLICATION_REFERENCE"))
    parsed = parser.parse_args(arguments)
    try:
        if parsed.candidate:
            (parsed.output / "candidate.json").unlink(missing_ok=True)
            proof = verify_application_reference(
                root=root or Path(__file__).resolve().parents[2], revision=parsed.application_reference,
            ) if parsed.application_reference is not None else None
            identity, current, runtime = measure_artifacts(
                context_path=parsed.context,
                executor=executor,
                inputs=parsed.inputs,
                ios_shards=parsed.ios_shards,
                output=parsed.output,
                root=root,
            )
            candidate: dict[str, JsonValue] = {
                "collection": asdict(identity),
                "kind": "baseline-candidate",
                "ios_runtime": asdict(runtime),
                "measurements": {
                    scope.value: {
                        "file_counters": {
                            name: asdict(counters)
                            for name, counters in current[scope].file_counters.items()
                        },
                        "files": list(current[scope].files),
                        "lines": asdict(current[scope].lines),
                        "regions": asdict(current[scope].regions),
                        **({"unmapped_files": list(current[scope].unmapped_files)} if current[scope].unmapped_files else {}),
                    }
                    for scope in Scope
                },
                "passed": None,
                "schema": 1,
                "toolchain": identity.toolchain,
            }
            if proof is not None:
                if proof.collection_revision != identity.revision:
                    raise ValueError("Application reference collection revision differs from artifacts")
                candidate["application_reference"] = {
                    "schema": 1,
                    "collection_revision": proof.collection_revision,
                    "revision": proof.revision,
                    "source_digest": proof.source_digest,
                    "verified_files": list(proof.verified_files),
                }
            (parsed.output / "candidate.json").write_text(json.dumps(candidate, indent=2, sort_keys=True) + "\n")
            print("Candidate measurements only; ratchets not evaluated")
            return 0
        passed = aggregate(
            baseline_path=parsed.baseline,
            context_path=parsed.context,
            executor=executor,
            inputs=parsed.inputs,
            ios_shards=parsed.ios_shards,
            output=parsed.output,
            root=root,
        )
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Coverage aggregation failed: {error}", file=sys.stderr)
        return 1
    print("Coverage gates passed" if passed else "Coverage gates failed")
    return 0 if passed else 1


def measure_artifacts(
    context_path: Path,
    inputs: Path,
    output: Path,
    executor: Executor | None = None,
    ios_shards: int = 2,
    root: Path | None = None,
    baseline_runtime: JsonValue = None,
) -> tuple[CollectionIdentity, dict[Scope, Measurement], IosRuntimeIdentity]:
    for name in ("report.json", "report.html", "candidate.json"):
        (output / name).unlink(missing_ok=True)
    suites = _collection_suites(inputs, ios_shards)
    root = root or Path(__file__).resolve().parents[2]
    context = decode_json(context_path.read_text())
    common_identity = _identity(context, str(root))
    if common_identity.source_digest != source_digest(root):
        raise ValueError("current checkout source fingerprint differs from coverage collection")
    sources = source_inventory(root)
    artifacts: list[ValidatedArtifact] = []
    mapping_sources: dict[str, tuple[str, ...]] = {}
    ios_enumerations: list[tuple[str, ...]] = []
    ios_plans: list[tuple[str, ...]] = []
    ios_runtimes: list[IosRuntimeIdentity] = []
    for suite in suites:
        manifest_path = inputs / suite / "manifest.json"
        manifest = decode_json(manifest_path.read_text())
        if not isinstance(manifest, dict) or not isinstance(manifest.get("identity"), dict):
            raise ValueError("missing artifact identity")
        identity = manifest["identity"]
        assert isinstance(identity, dict)
        source_root = identity.get("source_root")
        if not isinstance(source_root, str):
            raise ValueError("artifact source root must be a string")
        expected = _identity(context, source_root)
        artifacts.append(validate_artifact(manifest_path, expected, suite))
        recorded_sources = decode_json((manifest_path.parent / "source-inventory.json").read_text())
        if recorded_sources != list(sources):
            raise ValueError(f"artifact source inventory differs from current checkout: {suite}")
        stamp = decode_json((manifest_path.parent / "build-stamp.json").read_text())
        stamp_fields = {"identity", "mapping_sources", "objects", "platform", "schema", "sources"}
        if isinstance(stamp, dict) and suite == "package" and "package_test_targets" in stamp:
            stamp_fields.add("package_test_targets")
        if (
            not isinstance(stamp, dict)
            or set(stamp) != stamp_fields
            or type(stamp.get("schema")) is not int
            or stamp.get("schema") != 1
            or stamp.get("identity") != asdict(expected)
            or stamp.get("objects") != [
                str(path.relative_to(manifest_path.parent)) for path in artifacts[-1].objects
            ]
            or stamp.get("platform") != ("macOS" if suite == "package" else "iOS Simulator")
            or stamp.get("sources") != list(sources)
        ):
            raise ValueError(f"artifact build stamp differs from compiled source or object inventory: {suite}")
        mapping_sources[suite] = _strings(stamp["mapping_sources"], "mapping source inventory")
        validate_mapping_inventory(
            root, Scope.PACKAGE if suite == "package" else Scope.APP_HOSTED,
            mapping_sources[suite],
        )
        if suite == "package":
            enumerated = _string_inventory(manifest_path.parent / "enumerated-tests.json")
            methods = package_methods("\n".join(enumerated))
            targets = {method.split(".", 1)[0] for method in methods}
            object_names = {path.name for path in artifacts[-1].objects}
            recorded_targets = stamp.get("package_test_targets")
            if recorded_targets is not None and recorded_targets != sorted(targets):
                raise ValueError("package test target stamp differs from native inventory")
            if not targets.issubset(object_names) and not (
                "AuraKitPackageTests" in object_names and recorded_targets == sorted(targets)
            ):
                raise ValueError("package test target binaries are missing from mapping inventory")
            records = tuple(
                decode_json(line)
                for line in (manifest_path.parent / "native-events.jsonl").read_text().splitlines()
                if line.strip()
            )
            planned, completed = verify_package_events(methods, records)
            if (
                planned != _string_inventory(manifest_path.parent / "planned-tests.json")
                or completed != _string_inventory(manifest_path.parent / "completed-tests.json")
            ):
                raise ValueError("package native receipts differ from flattened test inventory")
        else:
            planned = _string_inventory(manifest_path.parent / "planned-tests.json")
            methods = tuple(test for test in planned if "#case:" not in test)
            summary = decode_json((manifest_path.parent / "test-summary.json").read_text())
            ios_runtimes.append(ios_runtime_identity(summary))
            completed = verify_ios_tests(
                methods,
                decode_json((manifest_path.parent / "test-inventory.json").read_text()),
                summary,
            )
            if (
                completed != planned
                or completed != _string_inventory(manifest_path.parent / "completed-tests.json")
            ):
                raise ValueError("iOS native receipts differ from flattened test inventory")
            ios_enumerations.append(enumerated_ios_tests(
                decode_json((manifest_path.parent / "enumerated-tests.json").read_text())
            ))
            ios_plans.append(methods)
    if any(enumeration != ios_enumerations[0] for enumeration in ios_enumerations):
        raise ValueError("iOS shard native enumerations differ")
    if any(runtime != ios_runtimes[0] for runtime in ios_runtimes):
        raise ValueError("iOS shard runtime versions or builds differ")
    if baseline_runtime is not None and baseline_runtime != asdict(ios_runtimes[0]):
        raise ValueError("Coverage baseline iOS runtime differs from the validated native runtime")
    verify_partition(ios_enumerations[0], ios_plans)
    executor = executor or SubprocessExecutor()
    output.mkdir(parents=True, exist_ok=True)
    for artifact in artifacts:
        mapping_export = executor.execute(_export_command((artifact,), None, root))
        (output / f"{artifact.suite}-mappings.json").write_text(mapping_export)
        mapped = measure_export(
            _normalize_export((artifact,), decode_json(mapping_export), root),
            str(root),
            Scope.TOTAL,
        )
        if mapped.files != mapping_sources[artifact.suite]:
            raise ValueError(
                f"artifact mapping source inventory differs from complete compiled mappings: {artifact.suite}"
            )
    package = artifacts[0]
    ios = artifacts[1:]
    package_profile = output / "package.profdata"
    ios_profile = output / "ios.profdata"
    total_profile = output / "total.profdata"
    executor.execute((
        "xcrun", "llvm-profdata", "merge", "-sparse", str(package.profile),
        "-o", str(package_profile),
    ))
    executor.execute((
        "xcrun", "llvm-profdata", "merge", "-sparse",
        *(str(artifact.profile) for artifact in ios), "-o", str(ios_profile),
    ))
    executor.execute((
        "xcrun", "llvm-profdata", "merge", "-sparse",
        *(str(artifact.profile) for artifact in artifacts), "-o", str(total_profile),
    ))
    current: dict[Scope, Measurement] = {}
    for scope, profile, mappings in (
        (Scope.PACKAGE, package_profile, [package]),
        (Scope.APP_HOSTED, ios_profile, ios),
        (Scope.TOTAL, total_profile, artifacts),
    ):
        command = _export_command(tuple(mappings), profile, root)
        exported = executor.execute(command)
        (output / f"{scope.value}.json").write_text(exported)
        current[scope] = measure_export(
            _normalize_export(tuple(mappings), decode_json(exported), root), str(root), scope,
        )
        alternate = executor.execute(_export_command(tuple(mappings), profile, root, reverse_objects=True))
        (output / f"{scope.value}-reversed-mappings.json").write_text(alternate)
        alternate_measurement = measure_export(
            _normalize_export(tuple(mappings), decode_json(alternate), root), str(root), scope,
        )
        # LLVM retains the first source/function mapping. Total deliberately uses
        # Granita's package-first precedence; category mappings remain order invariant.
        if scope != Scope.TOTAL and current[scope] != alternate_measurement:
            raise ValueError(f"incompatible order-dependent coverage mappings: {scope.value}")
        expected_sources = tuple(sorted({
            path
            for artifact in mappings
            for path in mapping_sources[artifact.suite]
            if scope != Scope.PACKAGE or path.startswith("AuraKit/Sources/")
        }))
        if current[scope].files != expected_sources:
            raise ValueError(f"measured mapping source inventory differs from complete mappings: {scope.value}")
        current[scope] = replace(
            current[scope],
            unmapped_files=validate_mapping_inventory(root, scope, current[scope].files),
        )
    return common_identity, current, ios_runtimes[0]


def _collection_suites(inputs: Path, ios_shards: int) -> tuple[str, ...]:
    if not (inputs / "package" / "manifest.json").is_file():
        raise ValueError(f"missing required package coverage artifact: {inputs}")
    if type(ios_shards) is not int or ios_shards not in (1, 2):
        raise ValueError("iOS shard count must be 1 or 2")
    suites = ("package", "ios-0", "ios-1") if ios_shards == 2 else ("package", "ios")
    if {path.name for path in inputs.iterdir()} != set(suites):
        raise ValueError(f"coverage collection inventory must contain exactly {suites}: {inputs}")
    return suites


def _export_command(
    artifacts: tuple[ValidatedArtifact, ...],
    profile: Path | None,
    root: Path,
    reverse_objects: bool = False,
) -> tuple[str, ...]:
    objects = tuple(path for artifact in artifacts for path in artifact.objects)
    if reverse_objects:
        objects = tuple(reversed(objects))
    remaps = tuple(
        f"--path-equivalence={source},{root}"
        for source in sorted({artifact.identity.source_root for artifact in artifacts})
    )
    return (
        "xcrun", "llvm-cov", "export", str(objects[0]),
        *(f"--object={path}" for path in objects[1:]),
        *((f"--instr-profile={profile}",) if profile is not None else ("--empty-profile",)),
        "--arch=arm64", "--check-binary-ids", "--summary-only", *remaps,
    )


def _identity(context: JsonValue, source_root: str) -> CollectionIdentity:
    if not isinstance(context, dict):
        raise ValueError("aggregation context must be an object")
    fields = ("architecture", "configuration", "revision", "run", "source_digest", "toolchain")
    values: dict[str, str] = {}
    for field in fields:
        value = context.get(field)
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"aggregation context {field} must be a nonempty string")
        values[field] = value
    return CollectionIdentity(
        architecture=values["architecture"],
        configuration=values["configuration"],
        revision=values["revision"],
        run=values["run"],
        source_digest=values["source_digest"],
        source_root=source_root,
        toolchain=values["toolchain"],
    )


def _normalize_export(
    artifacts: tuple[ValidatedArtifact, ...],
    export: JsonValue,
    root: Path,
) -> JsonValue:
    if not isinstance(export, dict):
        raise ValueError("LLVM export must be an object")
    units = export.get("data")
    if not isinstance(units, list):
        raise ValueError("LLVM export data must be a list")
    source_roots = sorted(
        {Path(artifact.identity.source_root) for artifact in artifacts},
        key=lambda path: -len(path.parts),
    )
    for unit in units:
        if not isinstance(unit, dict) or not isinstance(unit.get("files"), list):
            raise ValueError("LLVM export file inventory must be a list")
        files = unit["files"]
        assert isinstance(files, list)
        for file in files:
            if not isinstance(file, dict) or not isinstance(file.get("filename"), str):
                raise ValueError("LLVM export source filename must be a string")
            filename = file["filename"]
            assert isinstance(filename, str)
            path = Path(filename)
            for source in source_roots:
                if path.is_relative_to(source):
                    relative = path.relative_to(source)
                    if ".." in relative.parts:
                        raise ValueError("LLVM exported source path contains traversal")
                    file["filename"] = str(root / relative)
                    break
    return export


def _string_inventory(path: Path) -> tuple[str, ...]:
    values = decode_json(path.read_text())
    return _strings(values, str(path))


def _strings(values: JsonValue, label: str) -> tuple[str, ...]:
    if not isinstance(values, list) or not values:
        raise ValueError(f"nonempty string inventory required: {label}")
    result: list[str] = []
    for value in values:
        if not isinstance(value, str) or not value.strip() or value in result:
            raise ValueError(f"unique string inventory required: {label}")
        result.append(value)
    return tuple(sorted(result))


if __name__ == "__main__":
    raise SystemExit(main())
