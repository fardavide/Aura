from __future__ import annotations

import json
from dataclasses import FrozenInstanceError
import subprocess
import sys
from pathlib import Path

import pytest

import coverage_inventory as inventory


@pytest.fixture
def ios_summary() -> dict[str, inventory.JsonValue]:
    return {"devicesAndConfigurations": [{"device": {
        "architecture": "arm64", "deviceName": "AuraCoverage-isolated-run", "modelName": "iPhone 17",
        "osBuildNumber": "23F77", "osVersion": "26.5", "platform": "iOS Simulator",
    }, "expectedFailures": 0, "failedTests": 0, "passedTests": 1, "skippedTests": 0, "totalTestCount": 1}], "expectedFailures": 0, "failedTests": 0, "passedTests": 1, "result": "Passed", "skippedTests": 0, "totalTestCount": 1}


@pytest.fixture
def ios_tests() -> dict[str, inventory.JsonValue]:
    return {"testNodes": [{"children": [{"children": [{"nodeIdentifier": "Suite/method()", "nodeType": "Test Case", "result": "Passed"}], "nodeType": "Test Suite"}], "nodeType": "Test Plan"}]}


@pytest.fixture
def package_records() -> list[inventory.JsonValue]:
    return [
        {"kind": "test", "payload": {"id": "Module.Suite/test()/File.swift:12:6", "isParameterized": False, "kind": "function"}, "version": 0},
        {"kind": "event", "payload": {"kind": "runStarted"}, "version": 0},
        {"kind": "event", "payload": {"kind": "testStarted", "testID": "Module.Suite/test()/File.swift:12:6"}, "version": 0},
        {"kind": "event", "payload": {"kind": "testEnded", "testID": "Module.Suite/test()/File.swift:12:6"}, "version": 0},
        {"kind": "event", "payload": {"kind": "runEnded", "messages": [{"symbol": "pass", "text": "Test run with 1 test in 1 suite passed after 0.001 seconds."}]}, "version": 0},
    ]


@pytest.fixture
def parameterized_records(package_records: list[inventory.JsonValue]) -> list[inventory.JsonValue]:
    package_records[0] = {"kind": "test", "payload": {
        "_testCases": [{"id": "opaque argument 1"}, {"id": "opaque argument 2"}],
        "id": "Module.Suite/test()/File.swift:12:6", "isParameterized": True, "kind": "function",
    }, "version": 0}
    for case in ("opaque argument 1", "opaque argument 2"):
        for kind in ("testCaseStarted", "testCaseEnded"):
            package_records.insert(-2, {"kind": "event", "payload": {"_testCase": {"id": case}, "kind": kind, "testID": "Module.Suite/test()/File.swift:12:6"}, "version": 0})
    return package_records


class TestCoverageInventory:
    @pytest.mark.parametrize("build", [None, "", " ", False])
    def test_given_missing_ios_os_build_when_runtime_identity_read_then_rejects_incomplete_runtime(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
        build: inventory.JsonValue,
    ) -> None:
        # given
        devices = ios_summary["devicesAndConfigurations"]
        assert isinstance(devices, list)
        verdict = devices[0]
        assert isinstance(verdict, dict)
        device = verdict["device"]
        assert isinstance(device, dict)
        device["osBuildNumber"] = build
        # when
        with pytest.raises(ValueError, match="OS build"):
            inventory.ios_runtime_identity(ios_summary)
        # then

    def test_given_multiple_ios_devices_when_runtime_identity_read_then_rejects_ambiguous_runtime(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        devices = ios_summary["devicesAndConfigurations"]
        assert isinstance(devices, list)
        devices.append(devices[0])
        # when
        with pytest.raises(ValueError, match="exactly one"):
            inventory.ios_runtime_identity(ios_summary)
        # then

    def test_given_ios_runtime_identity_when_mutation_attempted_then_identity_is_immutable(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        runtime = inventory.ios_runtime_identity(ios_summary)
        # when
        with pytest.raises(FrozenInstanceError):
            setattr(runtime, "os_build", "different-build")
        # then

    def test_given_native_ios_summary_when_runtime_identity_read_then_preserves_compatible_runtime_fields(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        expected = inventory.IosRuntimeIdentity(
            architecture="arm64", model="iPhone 17", os_version="26.5", os_build="23F77", platform="iOS Simulator",
        )
        # when
        runtime = inventory.ios_runtime_identity(ios_summary)
        # then
        assert runtime == expected

    @pytest.mark.parametrize(("field", "value"), [
        ("platform", "macOS"), ("platform", None), ("modelName", "iPhone 17 Pro"),
        ("modelName", None), ("architecture", "x86_64"), ("architecture", None),
        ("osVersion", "27.0"), ("osVersion", "26"), ("osVersion", None),
    ])
    def test_given_ios_device_outside_preserved_runtime_when_verified_then_rejects_receipt(
        self: TestCoverageInventory,
        field: str,
        value: inventory.JsonValue,
        ios_summary: dict[str, inventory.JsonValue],
        ios_tests: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        devices = ios_summary["devicesAndConfigurations"]
        assert isinstance(devices, list)
        verdict = devices[0]
        assert isinstance(verdict, dict)
        device: dict[str, inventory.JsonValue] = {
            "architecture": "arm64", "deviceName": "AuraCoverage-isolated-run",
            "modelName": "iPhone 17", "osBuildNumber": "23F77", "osVersion": "26.5", "platform": "iOS Simulator",
        }
        device[field] = value
        verdict["device"] = device
        # when
        with pytest.raises(ValueError, match="device.*runtime"):
            inventory.verify_ios_tests(("AuraTests/Suite/method()",), ios_tests, ios_summary)
        # then

    def test_given_exported_native_json_when_weights_cli_runs_then_emits_measured_suite_weights(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
        tmp_path: Path,
    ) -> None:
        # given
        documents: dict[str, inventory.JsonValue] = {
            "expected": ["AuraTests/Suite/method()"],
            "summary": ios_summary,
            "tests": {"testNodes": [{"durationInSeconds": 2.5, "nodeIdentifier": "Suite/method()", "nodeType": "Test Case", "result": "Passed"}]},
        }
        for name, document in documents.items():
            (tmp_path / f"{name}.json").write_text(json.dumps(document))
        # when
        result = subprocess.run([
            sys.executable, str(Path(inventory.__file__)), "weights", "--expected", str(tmp_path / "expected.json"),
            "--tests", str(tmp_path / "tests.json"), "--summary", str(tmp_path / "summary.json"),
        ], capture_output=True, check=False, text=True)
        # then
        assert result.returncode == 0, result.stderr
        assert inventory.decode_json(result.stdout) == {"Suite": 2.5}

    @pytest.mark.parametrize("duration", [None, "1", False, -1, 0, float("inf"), float("nan")])
    def test_given_invalid_ios_measurement_when_weights_derived_then_rejects_duration(
        self: TestCoverageInventory,
        duration: inventory.JsonValue,
        ios_summary: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        tests: inventory.JsonValue = {"testNodes": [{"durationInSeconds": duration, "nodeIdentifier": "Suite/method()", "nodeType": "Test Case", "result": "Passed"}]}
        # when
        with pytest.raises(ValueError, match="duration"):
            inventory.ios_suite_durations(("AuraTests/Suite/method()",), tests, ios_summary)
        # then

    def test_given_measured_ios_methods_when_weights_derived_then_sums_each_suite_work(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        expected = ("AuraTests/Suite/one()", "AuraTests/Suite/two()", "AuraTests/Other/three()")
        ios_summary["passedTests"] = 3
        ios_summary["totalTestCount"] = 3
        tests: inventory.JsonValue = {"testNodes": [{"children": [
            {"durationInSeconds": 2.5, "nodeIdentifier": "Suite/one()", "nodeType": "Test Case", "result": "Passed"},
            {"durationInSeconds": 1.0, "nodeIdentifier": "Suite/two()", "nodeType": "Test Case", "result": "Passed"},
            {"durationInSeconds": 5.0, "nodeIdentifier": "Other/three()", "nodeType": "Test Case", "result": "Passed"},
        ], "nodeType": "Test Suite"}]}
        # when
        result = inventory.ios_suite_durations(expected, tests, ios_summary)
        # then
        assert result == {"Other": 5.0, "Suite": 3.5}

    def test_given_ios_summary_count_differs_from_methods_when_verified_then_rejects_receipt(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
        ios_tests: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        ios_summary["passedTests"] = 2
        ios_summary["totalTestCount"] = 2
        # when
        with pytest.raises(ValueError, match="count"):
            inventory.verify_ios_tests(("AuraTests/Suite/method()",), ios_tests, ios_summary)
        # then

    @pytest.mark.parametrize("location", ["summary", "device"])
    def test_given_known_ios_failure_when_verified_then_rejects_passed_summary(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
        ios_tests: dict[str, inventory.JsonValue],
        location: str,
    ) -> None:
        # given
        if location == "summary":
            ios_summary["expectedFailures"] = 1
        else:
            devices = ios_summary["devicesAndConfigurations"]
            assert isinstance(devices, list)
            device = devices[0]
            assert isinstance(device, dict)
            device["expectedFailures"] = 1
        # when
        with pytest.raises(ValueError):
            inventory.verify_ios_tests(("AuraTests/Suite/method()",), ios_tests, ios_summary)
        # then

    @pytest.mark.parametrize("identifier", [[], {}, None, 4])
    def test_given_untyped_swift_event_identifier_when_verified_then_rejects_record(
        self: TestCoverageInventory,
        identifier: inventory.JsonValue,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        package_records[2] = {"kind": "event", "payload": {"kind": "testStarted", "testID": identifier}, "version": 0}
        # when
        with pytest.raises(ValueError, match="identifier"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    def test_given_split_suite_when_partition_verified_then_rejects_shared_renderer(
        self: TestCoverageInventory,
    ) -> None:
        # given
        expected = ("AuraTests/Suite/one()", "AuraTests/Suite/two()")
        shards = ((expected[0],), (expected[1],))
        # when
        with pytest.raises(ValueError, match="whole suite"):
            inventory.verify_partition(expected, shards)
        # then

    def test_given_repeated_ios_argument_when_verified_then_rejects_duplicate_receipt(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        argument: inventory.JsonValue = {"nodeIdentifier": "same argument", "nodeType": "Arguments", "result": "Passed"}
        tests: inventory.JsonValue = {"testNodes": [{"children": [argument, argument], "nodeIdentifier": "Suite/method()", "nodeType": "Test Case", "result": "Passed"}]}
        # when
        with pytest.raises(ValueError, match="duplicate"):
            inventory.verify_ios_tests(("AuraTests/Suite/method()",), tests, ios_summary)
        # then

    def test_given_reversed_swift_case_events_when_verified_then_rejects_completion_order(
        self: TestCoverageInventory,
        parameterized_records: list[inventory.JsonValue],
    ) -> None:
        # given
        parameterized_records[3], parameterized_records[4] = parameterized_records[4], parameterized_records[3]
        # when
        with pytest.raises(ValueError, match="case completion"):
            inventory.verify_package_events(("Module.Suite/test()",), parameterized_records)
        # then

    def test_given_unknown_swift_event_when_verified_then_rejects_schema(
        self: TestCoverageInventory,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        package_records.insert(-1, {"kind": "event", "payload": {"kind": "unknownEvent"}, "version": 0})
        # when
        with pytest.raises(ValueError, match="schema"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    @pytest.mark.parametrize("kind", [None, "event", "unknown"])
    def test_given_invalid_descriptor_envelope_when_verified_then_rejects_schema(
        self: TestCoverageInventory,
        kind: inventory.JsonValue,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        record = package_records[0]
        assert isinstance(record, dict)
        record["kind"] = kind
        # when
        with pytest.raises(ValueError, match="schema"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    def test_given_repeated_parameter_descriptor_when_verified_then_counts_each_case_once(
        self: TestCoverageInventory,
        parameterized_records: list[inventory.JsonValue],
    ) -> None:
        # given
        parameterized_records.insert(0, parameterized_records[0])
        # when
        planned, completed = inventory.verify_package_events(("Module.Suite/test()",), parameterized_records)
        # then
        assert planned == completed
        assert len(planned) == 3

    def test_given_malformed_ios_expectation_when_verified_then_rejects_inventory(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
        ios_tests: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="inventory"):
            inventory.verify_ios_tests(("bad",), ios_tests, ios_summary)
        # then

    def test_given_duplicate_json_keys_when_decoded_then_rejects_ambiguous_value(
        self: TestCoverageInventory,
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="duplicate"):
            inventory.decode_json('{"values":{"result":"Failed","result":"Passed"}}')
        # then

    @pytest.mark.parametrize("source", ['{"count":NaN}', '[Infinity]', '1e999', '-Infinity'])
    def test_given_nonfinite_json_when_decoded_then_rejects_value(
        self: TestCoverageInventory,
        source: str,
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="finite"):
            inventory.decode_json(source)
        # then

    def test_given_recursive_native_json_when_decoded_then_preserves_typed_values(
        self: TestCoverageInventory,
    ) -> None:
        # given
        source = '{"values":[null,true,1,1.5,"method",{"nested":[]}]} '
        # when
        result = inventory.decode_json(source)
        # then
        assert result == {"values": [None, True, 1, 1.5, "method", {"nested": []}]}

    @pytest.mark.parametrize("parameterized", [None, "true", 0, 1])
    def test_given_untyped_parameter_flag_when_verified_then_rejects_descriptor(
        self: TestCoverageInventory,
        package_records: list[inventory.JsonValue],
        parameterized: inventory.JsonValue,
    ) -> None:
        # given
        package_records[0] = {"kind": "test", "payload": {"id": "Module.Suite/test()/File.swift:12:6", "isParameterized": parameterized, "kind": "function"}, "version": 0}
        # when
        with pytest.raises(ValueError, match="descriptor"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    def test_given_swift_method_outside_run_when_verified_then_rejects_completion(
        self: TestCoverageInventory,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        package_records[1], package_records[2] = package_records[2], package_records[1]
        # when
        with pytest.raises(ValueError, match="completion"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    def test_given_reversed_swift_method_events_when_verified_then_rejects_completion_order(
        self: TestCoverageInventory,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        package_records[2], package_records[3] = package_records[3], package_records[2]
        # when
        with pytest.raises(ValueError, match="completion"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    def test_given_swift_summary_count_mismatch_when_verified_then_rejects_verdict(
        self: TestCoverageInventory,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        package_records[-1] = {"kind": "event", "payload": {"kind": "runEnded", "messages": [{"symbol": "pass", "text": "Test run with 2 tests in 1 suite passed after 0.001 seconds."}]}, "version": 0}
        # when
        with pytest.raises(ValueError, match="run verdict"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    def test_given_successful_ios_argument_when_verified_then_preserves_argument_identifier(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        tests: inventory.JsonValue = {"testNodes": [{"children": [{"nodeIdentifier": "opaque argument 1", "nodeType": "Arguments", "result": "Passed"}], "nodeIdentifier": "Suite/method()", "nodeType": "Test Case", "result": "Passed"}]}
        # when
        result = inventory.verify_ios_tests(("AuraTests/Suite/method()",), tests, ios_summary)
        # then
        assert result == ("AuraTests/Suite/method()", "AuraTests/Suite/method()#case:opaque argument 1")

    @pytest.mark.parametrize("result", ["Failed", "Skipped", None])
    def test_given_unpassed_ios_argument_when_verified_then_rejects_completion(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
        result: inventory.JsonValue,
    ) -> None:
        # given
        tests: inventory.JsonValue = {"testNodes": [{"children": [{"nodeIdentifier": "argument 1", "nodeType": "Arguments", "result": result}], "nodeIdentifier": "Suite/method()", "nodeType": "Test Case", "result": "Passed"}]}
        # when
        with pytest.raises(ValueError, match="argument"):
            inventory.verify_ios_tests(("AuraTests/Suite/method()",), tests, ios_summary)
        # then

    @pytest.mark.parametrize("devices", [[], None, [{"failedTests": 1, "skippedTests": 0}], [{"failedTests": 0, "skippedTests": 1}], [{"failedTests": False, "skippedTests": 0}], [{}]])
    def test_given_incomplete_or_failed_ios_device_when_verified_then_rejects_verdict(
        self: TestCoverageInventory,
        devices: inventory.JsonValue,
        ios_summary: dict[str, inventory.JsonValue],
        ios_tests: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        ios_summary["devicesAndConfigurations"] = devices
        # when
        with pytest.raises(ValueError, match="device"):
            inventory.verify_ios_tests(("AuraTests/Suite/method()",), ios_tests, ios_summary)
        # then

    @pytest.mark.parametrize(("field", "value"), [("result", "Failed"), ("totalTestCount", 0), ("totalTestCount", 2), ("passedTests", 0), ("failedTests", 1), ("skippedTests", 1), ("totalTestCount", True), ("failedTests", False)])
    def test_given_unsuccessful_ios_summary_when_verified_then_rejects_verdict(
        self: TestCoverageInventory,
        field: str,
        ios_summary: dict[str, inventory.JsonValue],
        ios_tests: dict[str, inventory.JsonValue],
        value: inventory.JsonValue,
    ) -> None:
        # given
        ios_summary[field] = value
        # when
        with pytest.raises(ValueError, match="summary"):
            inventory.verify_ios_tests(("AuraTests/Suite/method()",), ios_tests, ios_summary)
        # then

    @pytest.mark.parametrize("identifiers", [[], ["Suite/method()", "Suite/method()"], ["Suite/other()"], ["Suite/method()", "Suite/other()"]])
    def test_given_different_ios_methods_when_verified_then_rejects_inventory(
        self: TestCoverageInventory,
        identifiers: list[str],
        ios_summary: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        nodes: list[inventory.JsonValue] = [{"nodeIdentifier": method, "nodeType": "Test Case", "result": "Passed"} for method in identifiers]
        # when
        with pytest.raises(ValueError, match="inventory"):
            inventory.verify_ios_tests(("AuraTests/Suite/method()",), {"testNodes": nodes}, ios_summary)
        # then

    @pytest.mark.parametrize("result", ["Failed", "Skipped", "Expected Failure", None])
    def test_given_unpassed_ios_method_when_verified_then_rejects_completion(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
        result: inventory.JsonValue,
    ) -> None:
        # given
        tests: inventory.JsonValue = {"testNodes": [{"nodeIdentifier": "Suite/method()", "nodeType": "Test Case", "result": result}]}
        # when
        with pytest.raises(ValueError, match="passed"):
            inventory.verify_ios_tests(("AuraTests/Suite/method()",), tests, ios_summary)
        # then

    def test_given_successful_ios_methods_when_verified_then_restores_target_prefix(
        self: TestCoverageInventory,
        ios_summary: dict[str, inventory.JsonValue],
        ios_tests: dict[str, inventory.JsonValue],
    ) -> None:
        # given
        expected = ("AuraTests/Suite/method()",)
        # when
        result = inventory.verify_ios_tests(expected, ios_tests, ios_summary)
        # then
        assert result == expected

    @pytest.mark.parametrize("messages", [[], [{"symbol": "fail", "text": "Test run with 1 test failed."}], [{"symbol": "pass", "text": "Test run with 0 tests in 0 suites passed after 0.001 seconds."}]])
    def test_given_unsuccessful_or_empty_swift_run_when_verified_then_rejects_verdict(
        self: TestCoverageInventory,
        messages: inventory.JsonValue,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        package_records[-1] = {"kind": "event", "payload": {"kind": "runEnded", "messages": messages}, "version": 0}
        # when
        with pytest.raises(ValueError, match="run verdict"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    @pytest.mark.parametrize("index", [1, 4])
    def test_given_unpaired_swift_run_when_verified_then_rejects_completion(
        self: TestCoverageInventory,
        index: int,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        package_records.pop(index)
        # when
        with pytest.raises(ValueError, match="run completion"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    @pytest.mark.parametrize("kind", ["issueRecorded", "testSkipped"])
    def test_given_failed_or_skipped_swift_event_when_verified_then_rejects_run(
        self: TestCoverageInventory,
        kind: str,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        package_records.insert(-1, {"kind": "event", "payload": {"kind": kind, "testID": "Module.Suite/test()/File.swift:12:6"}, "version": 0})
        # when
        with pytest.raises(ValueError, match="failed or skipped"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    def test_given_incremental_parameter_descriptor_when_verified_then_uses_final_case_plan(
        self: TestCoverageInventory,
        parameterized_records: list[inventory.JsonValue],
    ) -> None:
        # given
        parameterized_records.insert(0, {"kind": "test", "payload": {"id": "Module.Suite/test()/File.swift:12:6", "isParameterized": True, "kind": "function"}, "version": 0})
        # when
        planned, completed = inventory.verify_package_events(("Module.Suite/test()",), parameterized_records)
        # then
        assert planned == completed
        assert len(planned) == 3

    @pytest.mark.parametrize("cases", [None, [], [{"id": "one"}, {"id": "one"}]])
    def test_given_incomplete_parameter_descriptor_when_verified_then_rejects_case_plan(
        self: TestCoverageInventory,
        cases: inventory.JsonValue,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        package_records[0] = {"kind": "test", "payload": {"_testCases": cases, "id": "Module.Suite/test()/File.swift:12:6", "isParameterized": True, "kind": "function"}, "version": 0}
        # when
        with pytest.raises(ValueError, match="case plan"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    @pytest.mark.parametrize("index", [3, 4])
    @pytest.mark.parametrize("duplicate", [False, True])
    def test_given_missing_or_repeated_argument_event_when_verified_then_rejects_completion(
        self: TestCoverageInventory,
        duplicate: bool,
        index: int,
        parameterized_records: list[inventory.JsonValue],
    ) -> None:
        # given
        event = parameterized_records[index]
        if duplicate:
            parameterized_records.insert(index, event)
        else:
            parameterized_records.pop(index)
        # when
        with pytest.raises(ValueError, match="case completion"):
            inventory.verify_package_events(("Module.Suite/test()",), parameterized_records)
        # then

    def test_given_parameterized_methods_when_verified_then_preserves_descriptor_case_ids(
        self: TestCoverageInventory,
        parameterized_records: list[inventory.JsonValue],
    ) -> None:
        # given
        expected = ("Module.Suite/test()",)
        # when
        planned, completed = inventory.verify_package_events(expected, parameterized_records)
        # then
        assert planned == completed == ("Module.Suite/test()", "Module.Suite/test()#case:opaque argument 1", "Module.Suite/test()#case:opaque argument 2")

    def test_given_swift_suite_events_when_verified_then_excludes_suites_from_methods(
        self: TestCoverageInventory,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        package_records.insert(0, {"kind": "test", "payload": {"id": "Module.Suite", "kind": "suite"}, "version": 0})
        package_records.insert(3, {"kind": "event", "payload": {"kind": "testStarted", "testID": "Module.Suite"}, "version": 0})
        package_records.insert(-1, {"kind": "event", "payload": {"kind": "testEnded", "testID": "Module.Suite"}, "version": 0})
        # when
        planned, completed = inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then
        assert planned == completed == ("Module.Suite/test()",)

    @pytest.mark.parametrize("index", [2, 3])
    @pytest.mark.parametrize("duplicate", [False, True])
    def test_given_missing_or_repeated_method_event_when_verified_then_rejects_completion(
        self: TestCoverageInventory,
        duplicate: bool,
        index: int,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        event = package_records[index]
        if duplicate:
            package_records.insert(index, event)
        else:
            package_records.pop(index)
        # when
        with pytest.raises(ValueError, match="completion"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    @pytest.mark.parametrize("expected", [("Module.Suite/other()",), ("Module.Suite/test()", "Module.Suite/other()"), ("Module.Suite/test()", "Module.Suite/test()"), ()])
    def test_given_different_pre_run_methods_when_events_verified_then_rejects_inventory(
        self: TestCoverageInventory,
        expected: tuple[str, ...],
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="inventory"):
            inventory.verify_package_events(expected, package_records)
        # then

    @pytest.mark.parametrize("version", [1, "6.4", True, None])
    def test_given_incompatible_swift_event_schema_when_verified_then_rejects_schema(
        self: TestCoverageInventory,
        package_records: list[inventory.JsonValue],
        version: inventory.JsonValue,
    ) -> None:
        # given
        record = package_records[0]
        assert isinstance(record, dict)
        record["version"] = version
        # when
        with pytest.raises(ValueError, match="schema"):
            inventory.verify_package_events(("Module.Suite/test()",), package_records)
        # then

    def test_given_complete_swift_events_when_verified_then_receipts_match_listing(
        self: TestCoverageInventory,
        package_records: list[inventory.JsonValue],
    ) -> None:
        # given
        expected = ("Module.Suite/test()",)
        # when
        planned, completed = inventory.verify_package_events(expected, package_records)
        # then
        assert planned == completed == expected

    @pytest.mark.parametrize("listing", ["", "\n", "Build complete!\nModule.Suite/test()", "Module.Suite/test()\nModule.Suite/test()", "Suite/test()", "Module.Suite/test"])
    def test_given_invalid_swift_listing_when_parsed_then_rejects_inventory(
        self: TestCoverageInventory,
        listing: str,
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="inventory"):
            inventory.package_methods(listing)
        # then

    def test_given_swift_listing_when_parsed_then_preserves_full_method_names(
        self: TestCoverageInventory,
    ) -> None:
        # given
        listing = '\nTimelineTests.DayTests/`given midnight when rolled up then clipped`()\nExportsTests.StateTests/`given state then content`(state:)\n'
        # when
        result = inventory.package_methods(listing)
        # then
        assert result == ('ExportsTests.StateTests/`given state then content`(state:)', 'TimelineTests.DayTests/`given midnight when rolled up then clipped`()')

    @pytest.mark.parametrize("expected", [("AuraTests/A/a()", "AuraTests/A/a()"), ("bad",)])
    def test_given_invalid_methods_when_sharded_then_rejects_inventory(
        self: TestCoverageInventory,
        expected: tuple[str, ...],
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="inventory"):
            inventory.balanced_shards(expected, {"A": 1.0}, count=1)
        # then

    @pytest.mark.parametrize("shards", [(("AuraTests/A/a()",),), (("AuraTests/A/a()", "AuraTests/B/b()", "AuraTests/B/b()"),), (("AuraTests/A/a()", "AuraTests/B/b()", "AuraTests/C/c()"),)])
    def test_given_partial_or_duplicate_partition_when_verified_then_rejects_inventory(
        self: TestCoverageInventory,
        shards: tuple[tuple[str, ...], ...],
    ) -> None:
        # given
        expected = ("AuraTests/A/a()", "AuraTests/B/b()")
        # when
        with pytest.raises(ValueError, match="partition"):
            inventory.verify_partition(expected, shards)
        # then

    @pytest.mark.parametrize("count", [0, -1, 2, True])
    def test_given_invalid_shard_count_when_sharded_then_rejects_count(
        self: TestCoverageInventory,
        count: int,
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="count"):
            inventory.balanced_shards(("AuraTests/A/a()",), {"A": 1.0}, count)
        # then

    @pytest.mark.parametrize("durations", [{}, {"A": 0.0}, {"A": -1.0}, {"A": float("inf")}, {"A": float("nan")}, {"A": True}])
    def test_given_invalid_suite_weight_when_sharded_then_rejects_weight(
        self: TestCoverageInventory,
        durations: dict[str, float],
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="weight"):
            inventory.balanced_shards(("AuraTests/A/a()",), durations, count=1)
        # then

    def test_given_suite_weights_when_sharded_then_balances_whole_suites_stably(
        self: TestCoverageInventory,
    ) -> None:
        # given
        expected = ("AuraTests/C/c()", "AuraTests/A/a()", "AuraTests/B/b()", "AuraTests/A/b()")
        durations = {"A": 10.0, "B": 6.0, "C": 4.0}
        # when
        result = inventory.balanced_shards(expected, durations)
        # then
        assert result == (("AuraTests/A/a()", "AuraTests/A/b()"), ("AuraTests/B/b()", "AuraTests/C/c()"))

    @pytest.mark.parametrize("plan", [
        {"errors": ["enumeration failed"], "values": []},
        {"errors": [], "values": []},
        {"errors": [], "values": [{"disabledTests": [{"identifier": "AuraTests/A/a()"}], "enabledTests": [{"identifier": "AuraTests/A/a()"}]}]},
        {"errors": [], "values": [{"disabledTests": [], "enabledTests": [{"identifier": "AuraTests/A/a()"}, {"identifier": "AuraTests/A/a()"}]}]},
        {"errors": [], "values": [{"disabledTests": [], "enabledTests": [{"identifier": "Suite/method"}]}]},
        {"values": [{"enabledTests": [{"identifier": "AuraTests/A/a()"}]}]},
        {"errors": [], "values": [{"disabledTests": "", "enabledTests": [{"identifier": "AuraTests/A/a()"}]}]},
    ])
    def test_given_invalid_ios_plan_when_enumerated_then_rejects_inventory(
        self: TestCoverageInventory,
        plan: inventory.JsonValue,
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError):
            inventory.enumerated_ios_tests(plan)
        # then

    def test_given_enabled_ios_methods_when_enumerated_then_returns_sorted_inventory(
        self: TestCoverageInventory,
    ) -> None:
        # given
        plan = {
            "errors": [],
            "values": [{"disabledTests": [], "enabledTests": [
                {"identifier": "AuraTests/Beta/two()"},
                {"identifier": "AuraTests/Alpha/one()"},
            ]}],
        }
        # when
        result = inventory.enumerated_ios_tests(plan)
        # then
        assert result == ("AuraTests/Alpha/one()", "AuraTests/Beta/two()")
