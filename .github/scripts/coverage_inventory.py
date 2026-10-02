"""Fail-closed inventories for native coverage test executions."""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from math import isfinite
from pathlib import Path

JsonValue = bool | dict[str, "JsonValue"] | float | int | list["JsonValue"] | None | str


@dataclass(frozen=True)
class IosRuntimeIdentity:
    architecture: str
    model: str
    os_version: str
    os_build: str
    platform: str


def balanced_shards(
    expected: Sequence[str],
    durations: Mapping[str, float],
    count: int = 2,
) -> tuple[tuple[str, ...], ...]:
    if not expected or len(set(expected)) != len(expected) or any(
        not re.fullmatch(r"[^/\s]+/[^/\s]+/[^/]+\([^/]*\)", method) for method in expected
    ):
        raise ValueError("invalid iOS inventory for sharding")
    suites: dict[str, list[str]] = {}
    for method in expected:
        suite = method.split("/")[1]
        suites.setdefault(suite, []).append(method)
    if type(count) is not int or not 0 < count <= len(suites):
        raise ValueError("shard count must be positive and at most the suite count")
    for suite in suites:
        weight = durations.get(suite)
        if isinstance(weight, bool) or not isinstance(weight, (int, float)) or not isfinite(weight) or weight <= 0:
            raise ValueError(f"missing or invalid duration weight for {suite}")
    shards: list[list[str]] = [[] for _ in range(count)]
    weights = [0.0] * count
    for suite in sorted(suites, key=lambda item: (-durations[item], item)):
        index = min(range(count), key=lambda item: (weights[item], item))
        shards[index].extend(suites[suite])
        weights[index] += durations[suite]
    result = tuple(tuple(sorted(shard)) for shard in shards)
    verify_partition(expected, result)
    return result


def decode_json(source: str) -> JsonValue:
    decoded: object = json.loads(source, object_pairs_hook=_json_object)
    return _json_value(decoded)


def enumerated_ios_tests(plan: JsonValue) -> tuple[str, ...]:
    if not isinstance(plan, dict):
        raise ValueError("enumeration must be an object")
    if plan.get("errors") != []:
        raise ValueError("enumeration errors must be an empty list")
    values = plan.get("values")
    if not isinstance(values, list):
        raise ValueError("enumeration values must be a list")
    methods: list[str] = []
    for value in values:
        if not isinstance(value, dict):
            raise ValueError("enumeration value must be an object")
        if value.get("disabledTests") != []:
            raise ValueError("disabled tests invalidate coverage inventory")
        tests = value.get("enabledTests")
        if not isinstance(tests, list):
            raise ValueError("enabledTests must be a list")
        for test in tests:
            if not isinstance(test, dict) or not isinstance(test.get("identifier"), str):
                raise ValueError("test identifier must be a string")
            identifier = test["identifier"]
            assert isinstance(identifier, str)
            if not re.fullmatch(r"[^/\s]+/[^/\s]+/[^/]+\([^/]*\)", identifier):
                raise ValueError("malformed iOS method identifier")
            methods.append(identifier)
    if not methods or len(set(methods)) != len(methods):
        raise ValueError("empty or duplicate iOS inventory")
    return tuple(sorted(methods))


def ios_suite_durations(
    expected: Sequence[str],
    inventory: JsonValue,
    summary: JsonValue,
) -> dict[str, float]:
    verify_ios_tests(expected, inventory, summary)
    nodes = _object(inventory, "iOS inventory").get("testNodes")
    assert isinstance(nodes, list)
    pending = list(nodes)
    durations: dict[str, float] = {}
    while pending:
        node = _object(pending.pop(), "test node")
        if node.get("nodeType") == "Test Case":
            identifier = node.get("nodeIdentifier")
            duration = node.get("durationInSeconds")
            assert isinstance(identifier, str)
            if isinstance(duration, bool) or not isinstance(duration, (int, float)) or not isfinite(duration) or duration < 0:
                raise ValueError("iOS method duration must be finite and nonnegative")
            suite = identifier.split("/", 1)[0]
            durations[suite] = durations.get(suite, 0.0) + duration
        children = node.get("children", [])
        assert isinstance(children, list)
        pending.extend(children)
    if any(not isfinite(duration) or duration <= 0 for duration in durations.values()):
        raise ValueError("iOS suite duration must be finite and positive")
    return dict(sorted(durations.items()))


def main(arguments: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    weights = commands.add_parser("weights")
    weights.add_argument("--expected", required=True, type=Path)
    weights.add_argument("--summary", required=True, type=Path)
    weights.add_argument("--tests", required=True, type=Path)
    options = parser.parse_args(list(arguments) if arguments is not None else None)
    expected = decode_json(options.expected.read_text())
    if not isinstance(expected, list) or not all(isinstance(method, str) for method in expected):
        raise ValueError("expected inventory must be a JSON string list")
    methods = tuple(method for method in expected if isinstance(method, str))
    durations = ios_suite_durations(methods, decode_json(options.tests.read_text()), decode_json(options.summary.read_text()))
    print(json.dumps(durations, sort_keys=True))
    return 0


def package_methods(listing: str) -> tuple[str, ...]:
    methods = tuple(sorted(line.strip() for line in listing.splitlines() if line.strip()))
    if not methods or len(set(methods)) != len(methods) or any(
        not re.fullmatch(r"[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+/(?:`[^`]+`|[A-Za-z_]\w*)\([^()]*\)", method)
        for method in methods
    ):
        raise ValueError("empty, duplicate, or malformed Swift package inventory")
    return methods


def ios_runtime_identity(summary: JsonValue) -> IosRuntimeIdentity:
    verdict = _object(summary, "iOS summary")
    devices = verdict.get("devicesAndConfigurations")
    if not isinstance(devices, list) or len(devices) != 1:
        raise ValueError("iOS device runtime requires exactly one device")
    runtime = _object(_object(devices[0], "iOS device").get("device"), "iOS device runtime")
    version = runtime.get("osVersion")
    build = runtime.get("osBuildNumber")
    if runtime.get("platform") != "iOS Simulator" or runtime.get("modelName") != "iPhone 17" or runtime.get("architecture") != "arm64" or not isinstance(version, str) or not version.startswith("26."):
        raise ValueError("iOS device runtime must be an arm64 iPhone 17 simulator running iOS 26")
    if not isinstance(build, str) or not build.strip():
        raise ValueError("iOS device runtime requires a nonempty OS build")
    return IosRuntimeIdentity("arm64", "iPhone 17", version, build, "iOS Simulator")


def verify_ios_tests(
    expected: Sequence[str],
    inventory: JsonValue,
    summary: JsonValue,
) -> tuple[str, ...]:
    if any(not re.fullmatch(r"[^/\s]+/[^/\s]+/[^/]+\([^/]*\)", method) for method in expected):
        raise ValueError("malformed iOS expected inventory")
    verdict = _object(summary, "iOS summary")
    if verdict.get("result") != "Passed":
        raise ValueError("iOS summary result must be Passed")
    for field in ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures"):
        if type(verdict.get(field)) is not int:
            raise ValueError(f"iOS summary {field} must be an integer")
    total = verdict.get("totalTestCount")
    assert isinstance(total, int)
    if total <= 0 or total != verdict.get("passedTests") or any(verdict.get(field) != 0 for field in ("failedTests", "skippedTests", "expectedFailures")):
        raise ValueError("iOS summary must contain only positive successful tests")
    devices = verdict.get("devicesAndConfigurations")
    if not isinstance(devices, list) or not devices:
        raise ValueError("iOS device verdicts are missing")
    for device in devices:
        fields = _object(device, "iOS device")
        for field in ("failedTests", "skippedTests", "expectedFailures"):
            if type(fields.get(field)) is not int or fields.get(field) != 0:
                raise ValueError("iOS device has failures or skips")
        runtime = _object(fields.get("device"), "iOS device runtime")
        version = runtime.get("osVersion")
        if runtime.get("platform") != "iOS Simulator" or runtime.get("modelName") != "iPhone 17" or runtime.get("architecture") != "arm64" or not isinstance(version, str) or not version.startswith("26."):
            raise ValueError("iOS device runtime must be an arm64 iPhone 17 simulator running iOS 26")
    nodes = _object(inventory, "iOS inventory").get("testNodes")
    if not isinstance(nodes, list):
        raise ValueError("iOS inventory testNodes must be a list")
    completed: list[str] = []
    arguments: list[str] = []
    pending: list[tuple[JsonValue, str | None]] = [(node, None) for node in nodes]
    while pending:
        value, owner = pending.pop()
        node = _object(value, "test node")
        if node.get("nodeType") == "Test Case":
            if node.get("result") != "Passed":
                raise ValueError("iOS method did not pass; every method must be passed")
            identifier = node.get("nodeIdentifier")
            if not isinstance(identifier, str):
                raise ValueError("iOS method identifier must be a string")
            completed.append(identifier)
            owner = identifier
        elif node.get("nodeType") == "Arguments":
            if node.get("result") != "Passed":
                raise ValueError("iOS argument did not pass")
            argument_id = node.get("nodeIdentifier")
            if owner is None or not isinstance(argument_id, str) or not argument_id:
                raise ValueError("iOS argument identifier or owning method is missing")
            for method in expected:
                if method.split("/", 1)[1] == owner:
                    arguments.append(f"{method}#case:{argument_id}")
        children = node.get("children", [])
        if not isinstance(children, list):
            raise ValueError("test node children must be a list")
        pending.extend((child, owner) for child in children)
    names = [method.split("/", 1)[1] for method in expected]
    if not expected or len(set(expected)) != len(expected) or Counter(completed) != Counter(names):
        raise ValueError("iOS result inventory differs from exact plan")
    if len(set(arguments)) != len(arguments):
        raise ValueError("duplicate iOS argument receipt")
    if total != len(completed):
        raise ValueError("iOS summary count differs from completed method count")
    return tuple(sorted([*expected, *arguments]))


def verify_package_events(
    expected: Sequence[str],
    records: Sequence[JsonValue],
) -> tuple[tuple[str, ...], tuple[str, ...]]:
    methods: list[str] = []
    ended: list[str] = []
    started: list[str] = []
    planned_cases: list[str] = []
    completed_cases: list[str] = []
    started_cases: list[str] = []
    parameterized: set[str] = set()
    active_methods: set[str] = set()
    active_cases: set[str] = set()
    active_runs = 0
    finished_runs = 0
    passed_run_methods = 0
    suites: set[str] = set()
    for record in records:
        payload = _object(_object(record, "record").get("payload"), "payload")
        identifier = payload.get("id")
        if payload.get("kind") == "suite" and isinstance(identifier, str):
            suites.add(identifier)
    for record in records:
        envelope = _object(record, "record")
        if type(envelope.get("version")) is not int or envelope.get("version") != 0:
            raise ValueError("only Swift Testing event schema version 0 is supported")
        payload = _object(envelope.get("payload"), "payload")
        kind = payload.get("kind")
        envelope_kind = envelope.get("kind")
        if envelope_kind not in ("test", "event") or (envelope_kind == "test") != (kind in ("function", "suite")):
            raise ValueError("Swift Testing schema has an invalid record kind")
        if envelope_kind == "event" and kind not in (
            "runStarted", "runEnded", "testStarted", "testEnded", "testCaseStarted", "testCaseEnded", "issueRecorded", "testSkipped",
        ):
            raise ValueError("Swift Testing schema has an unknown event kind")
        if kind in ("issueRecorded", "testSkipped"):
            raise ValueError("Swift test failed or skipped")
        test_id = payload.get("testID")
        if kind in ("testStarted", "testEnded", "testCaseStarted", "testCaseEnded") and not isinstance(test_id, str):
            raise ValueError("Swift event test identifier must be a string")
        if kind in ("testStarted", "testEnded", "testCaseStarted", "testCaseEnded") and active_runs != 1:
            raise ValueError("package run completion contains a test outside a single active run")
        if kind == "runStarted":
            active_runs += 1
        elif kind == "runEnded":
            active_runs -= 1
            finished_runs += 1
            if active_runs < 0:
                raise ValueError("package run completion has no start")
            messages = payload.get("messages")
            if not isinstance(messages, list) or not messages:
                raise ValueError("package run verdict messages are missing")
            run_counts: list[int] = []
            for message in messages:
                fields = _object(message, "run verdict message")
                text = fields.get("text")
                match = re.fullmatch(r"Test run with (\d+) tests? in \d+ suites? passed after .+ seconds\.", text) if isinstance(text, str) else None
                if fields.get("symbol") == "pass" and match:
                    run_counts.append(int(match.group(1)))
                else:
                    raise ValueError("package run verdict was not passed")
            if len(run_counts) != 1:
                raise ValueError("package run verdict must have one summary")
            passed_run_methods += run_counts[0]
        if kind == "function":
            method = _package_method(payload.get("id"))
            if type(payload.get("isParameterized")) is not bool:
                raise ValueError("package descriptor isParameterized must be boolean")
            if method not in methods:
                methods.append(method)
            if payload.get("isParameterized") is True:
                parameterized.add(method)
                cases = payload.get("_testCases")
                if isinstance(cases, list):
                    descriptor_cases: list[str] = []
                    for case in cases:
                        case_id = _object(case, "parameter case").get("id")
                        if not isinstance(case_id, str) or not case_id:
                            raise ValueError("parameter case id must be a nonempty string")
                        descriptor_cases.append(f"{method}#case:{case_id}")
                    if len(set(descriptor_cases)) != len(descriptor_cases):
                        raise ValueError("package parameter case plan contains duplicates")
                    planned_cases.extend(case for case in descriptor_cases if case not in planned_cases)
        elif kind == "testEnded" and test_id not in suites:
            method = _package_method(test_id)
            if method not in active_methods:
                raise ValueError("package method completion has no unmatched start")
            active_methods.remove(method)
            ended.append(method)
        elif kind == "testStarted" and test_id not in suites:
            method = _package_method(test_id)
            active_methods.add(method)
            started.append(method)
        elif kind in ("testCaseStarted", "testCaseEnded"):
            method = _package_method(test_id)
            case_id = _object(payload.get("_testCase"), "parameter case").get("id")
            if not isinstance(case_id, str) or not case_id:
                raise ValueError("parameter case id must be a nonempty string")
            case_identifier = f"{method}#case:{case_id}"
            if kind == "testCaseStarted":
                active_cases.add(case_identifier)
                started_cases.append(case_identifier)
            else:
                if case_identifier not in active_cases:
                    raise ValueError("package case completion has no unmatched start")
                active_cases.remove(case_identifier)
                completed_cases.append(case_identifier)
    if not expected or len(set(expected)) != len(expected) or set(methods) != set(expected):
        raise ValueError("package descriptor inventory differs from pre-run listing")
    if active_runs or not finished_runs:
        raise ValueError("package run completion is missing")
    if passed_run_methods <= 0 or passed_run_methods != len(expected):
        raise ValueError("package run verdict count differs from expected successful tests")
    if len(set(planned_cases)) != len(planned_cases) or any(
        not any(case.startswith(f"{method}#case:") for case in planned_cases)
        for method in parameterized
    ):
        raise ValueError("package parameter case plan is empty or duplicated")
    if Counter(started) != Counter(expected) or Counter(ended) != Counter(expected):
        raise ValueError("package method completion is missing, repeated, or unexpected")
    if Counter(started_cases) != Counter(planned_cases) or Counter(completed_cases) != Counter(planned_cases):
        raise ValueError("package case completion is missing, repeated, or unexpected")
    return tuple(sorted(methods + planned_cases)), tuple(sorted(ended + completed_cases))


def verify_partition(expected: Sequence[str], shards: Sequence[Sequence[str]]) -> None:
    flattened = [method for shard in shards for method in shard]
    if not expected or len(set(expected)) != len(expected) or Counter(expected) != Counter(flattened):
        raise ValueError("shard partition differs from exact inventory")
    owners: dict[str, int] = {}
    for index, shard in enumerate(shards):
        for method in shard:
            suite = method.split("/")[1]
            if suite in owners and owners[suite] != index:
                raise ValueError("shard partition must preserve each whole suite")
            owners[suite] = index


def _json_object(pairs: list[tuple[str, JsonValue]]) -> dict[str, JsonValue]:
    fields: dict[str, JsonValue] = {}
    for key, value in pairs:
        if key in fields:
            raise ValueError(f"duplicate JSON object key: {key}")
        fields[key] = value
    return fields


def _json_value(value: object) -> JsonValue:
    if isinstance(value, float) and not isfinite(value):
        raise ValueError("JSON numbers must be finite")
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    if isinstance(value, list):
        return [_json_value(item) for item in value]
    if isinstance(value, dict):
        fields: dict[str, JsonValue] = {}
        for key, item in value.items():
            if not isinstance(key, str):
                raise ValueError("JSON object keys must be strings")
            fields[key] = _json_value(item)
        return fields
    raise ValueError("unsupported JSON value")


def _object(value: JsonValue, label: str) -> dict[str, JsonValue]:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return value


def _package_method(identifier: JsonValue) -> str:
    if not isinstance(identifier, str):
        raise ValueError("package method id must be a string")
    method, separator, location = identifier.rpartition("/")
    if separator and re.fullmatch(r"[^/]+\.swift:[1-9]\d*:[1-9]\d*", location):
        identifier = method
    return package_methods(identifier)[0]


if __name__ == "__main__":
    raise SystemExit(main())
