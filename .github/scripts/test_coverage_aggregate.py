from __future__ import annotations

from collections.abc import Iterator
from dataclasses import asdict, dataclass
from hashlib import sha256
import json
from pathlib import Path
import subprocess
import sys

import pytest

from coverage_aggregate import aggregate
from coverage_artifacts import CollectionIdentity, write_manifest
from coverage_inventory import JsonValue
from coverage_products import source_digest
from coverage_report import Scope


@dataclass
class FakeExecutor:
    commands: list[tuple[str, ...]]
    root: Path
    order_dependent_total: bool = False
    recorded_roots: bool = False

    def execute(self: FakeExecutor, command: tuple[str, ...]) -> str:
        self.commands.append(command)
        if "llvm-cov" not in command:
            return ""
        filenames = ("AuraKit/Sources/Feature/Domain.swift",)
        if any("/ios" in argument or "/total" in argument for argument in command):
            filenames = ("Aura/App.swift", *filenames)
        export_root = self.root
        if self.recorded_roots:
            equivalence = next(argument for argument in command if argument.startswith("--path-equivalence="))
            export_root = Path(equivalence.split("=", 1)[1].split(",", 1)[0])
        regions = {"count": 2, "covered": 2}
        if (
            self.order_dependent_total
            and any("/total.profdata" in argument for argument in command)
            and "/ios-" in command[3]
        ):
            regions = {"count": 3, "covered": 1}
        return json.dumps({"data": [{"files": [
            {"filename": str(export_root / name), "summary": {
                "lines": {"count": 2, "covered": 2},
                "regions": regions,
            }} for name in filenames
        ]}]})


@dataclass
class AggregationScenario:
    baseline_path: Path
    context_path: Path
    executor: FakeExecutor
    inputs: Path
    output: Path
    root: Path

    def aggregate(self: AggregationScenario) -> bool:
        return aggregate(
            baseline_path=self.baseline_path,
            context_path=self.context_path,
            executor=self.executor,
            inputs=self.inputs,
            output=self.output,
            root=self.root,
        )

    def identity(self: AggregationScenario, suite: str) -> CollectionIdentity:
        return CollectionIdentity(
            architecture="arm64",
            configuration="Debug",
            revision="revision",
            run="run-1",
            source_digest=source_digest(self.root),
            source_root=f"/runner/{suite}",
            toolchain="Xcode 26",
        )

    def reseal(self: AggregationScenario, suite: str) -> None:
        directory = self.inputs / suite
        write_manifest(directory, self.identity(suite), suite)


@pytest.fixture
def scenario(tmp_path: Path) -> AggregationScenario:
    root = tmp_path / "root"
    sources = ("Aura/App.swift", "AuraKit/Sources/Feature/Domain.swift")
    for name in sources:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("struct Source {}")
    inputs = tmp_path / "inputs"
    context_path = tmp_path / "context.json"
    context_path.write_text(json.dumps({
        "architecture": "arm64",
        "configuration": "Debug",
        "revision": "revision",
        "run": "run-1",
        "source_digest": source_digest(root),
        "source_root": str(root),
        "toolchain": "Xcode 26",
    }))
    baseline_path = tmp_path / "baseline.json"
    baseline_path.write_text(json.dumps({
        "ios_runtime": {
            "architecture": "arm64",
            "model": "iPhone 17",
            "os_build": "23F77",
            "os_version": "26.5",
            "platform": "iOS Simulator",
        },
        "measurements": {
            scope.value: {"files": list(sources[1:] if scope == Scope.PACKAGE else sources), "lines": {"count": 2, "covered": 1}, "regions": {"count": 2, "covered": 1}}
            for scope in Scope
        },
        "passed": True,
        "schema": 1,
        "toolchain": "Xcode 26",
    }))
    result = AggregationScenario(
        baseline_path=baseline_path,
        context_path=context_path,
        executor=FakeExecutor(commands=[], root=root),
        inputs=inputs,
        output=tmp_path / "output",
        root=root,
    )
    full_enumeration: JsonValue = {"errors": [], "values": [{
        "disabledTests": [],
        "enabledTests": [{"identifier": "AuraTests/A/a()"}, {"identifier": "AuraTests/B/b()"}],
    }]}
    for suite, method in (("package", "Module.Suite/test()"), ("ios-0", "AuraTests/A/a()"), ("ios-1", "AuraTests/B/b()")):
        directory = inputs / suite
        (directory / "objects").mkdir(parents=True)
        object_name = "Module" if suite == "package" else "AuraTests"
        (directory / "objects" / object_name).write_bytes(b"host mapping" if suite == "package" else b"ios mapping")
        (directory / "profile.profdata").write_bytes(b"fake profile used only by fake executor")
        for filename in ("completed-tests.json", "planned-tests.json"):
            (directory / filename).write_text(json.dumps([method]))
        (directory / "source-inventory.json").write_text(json.dumps(sources))
        if suite == "package":
            (directory / "enumerated-tests.json").write_text(json.dumps([method]))
            events: tuple[JsonValue, ...] = (
                {"kind": "test", "payload": {"id": method, "isParameterized": False, "kind": "function"}, "version": 0},
                {"kind": "event", "payload": {"kind": "runStarted"}, "version": 0},
                {"kind": "event", "payload": {"kind": "testStarted", "testID": method}, "version": 0},
                {"kind": "event", "payload": {"kind": "testEnded", "testID": method}, "version": 0},
                {"kind": "event", "payload": {"kind": "runEnded", "messages": [{"symbol": "pass", "text": "Test run with 1 test in 1 suite passed after 0.001 seconds."}]}, "version": 0},
            )
            (directory / "native-events.jsonl").write_text("\n".join(json.dumps(event) for event in events))
        else:
            (directory / "enumerated-tests.json").write_text(json.dumps(full_enumeration))
            (directory / "test-summary.json").write_text(json.dumps({
                "devicesAndConfigurations": [{
                    "device": {
                        "architecture": "arm64", "deviceName": "AuraCoverage-isolated-run",
                        "modelName": "iPhone 17", "osBuildNumber": "23F77",
                        "osVersion": "26.5", "platform": "iOS Simulator",
                    },
                    "expectedFailures": 0, "failedTests": 0, "skippedTests": 0,
                }],
                "expectedFailures": 0,
                "failedTests": 0, "passedTests": 1, "result": "Passed", "skippedTests": 0, "totalTestCount": 1,
            }))
            (directory / "test-inventory.json").write_text(json.dumps({"testNodes": [{
                "nodeIdentifier": method.split("/", 1)[1], "nodeType": "Test Case", "result": "Passed",
            }]}))
        (directory / "build-stamp.json").write_text(json.dumps({
            "identity": asdict(result.identity(suite)),
            "mapping_sources": list(sources[1:] if suite == "package" else sources),
            "objects": [f"objects/{object_name}"],
            "platform": "macOS" if suite == "package" else "iOS Simulator",
            "schema": 1,
            "sources": list(sources),
        }))
        result.reseal(suite)
    return result


class TestCoverageAggregate:
    def test_given_application_reference_when_candidate_is_measured_then_retains_verified_proof_without_relabeling_collection(
        self: TestCoverageAggregate,
        monkeypatch: pytest.MonkeyPatch,
        scenario: AggregationScenario,
    ) -> None:
        # given
        import coverage_aggregate
        from coverage_inventory import decode_json
        from coverage_products import ApplicationReference

        application_revision = "1" * 40
        verified_files = ("Aura/App.swift", "AuraKit/Sources/Feature/Domain.swift")
        proof = ApplicationReference(
            collection_revision="revision",
            revision=application_revision,
            source_digest="a" * 64,
            verified_files=verified_files,
        )
        verifications: list[tuple[Path, str]] = []

        def verify_application_reference(root: Path, revision: str) -> ApplicationReference:
            verifications.append((root, revision))
            return proof

        monkeypatch.setattr(
            coverage_aggregate, "verify_application_reference", verify_application_reference, raising=False,
        )

        # when
        exit_code = coverage_aggregate.main(
            arguments=(
                "--candidate", "--application-reference", application_revision,
                "--context", str(scenario.context_path), "--inputs", str(scenario.inputs),
                "--output", str(scenario.output),
            ),
            executor=scenario.executor,
            root=scenario.root,
        )

        # then
        assert exit_code == 0
        assert verifications == [(scenario.root, application_revision)]
        candidate = decode_json((scenario.output / "candidate.json").read_text())
        assert isinstance(candidate, dict)
        assert candidate.get("application_reference") == {
            "collection_revision": "revision",
            "revision": application_revision,
            "schema": 1,
            "source_digest": "a" * 64,
            "verified_files": list(verified_files),
        }
        collection = candidate.get("collection")
        assert isinstance(collection, dict)
        assert collection.get("revision") == "revision"
        assert collection.get("revision") != application_revision

    def test_given_reviewed_zero_mapping_source_when_aggregated_then_preserves_complete_source_inventory_without_changing_counters(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_inventory import decode_json

        unmapped_source = "AuraKit/Sources/Feature/RecordingLoading.swift"
        source_path = scenario.root / unmapped_source
        source_path.write_text("protocol RecordingLoading { func load() }\n")
        ledger_path = scenario.root / ".github/coverage/unmapped-sources.json"
        ledger_path.parent.mkdir(parents=True)
        ledger_path.write_text(json.dumps({
            "entries": [{
                "path": unmapped_source,
                "reason": "Protocol requirements only; no handwritten implementations.",
                "scopes": sorted(scope.value for scope in Scope),
                "sha256": sha256(source_path.read_bytes()).hexdigest(),
            }],
            "schema": 1,
        }))
        sources = ["Aura/App.swift", "AuraKit/Sources/Feature/Domain.swift", unmapped_source]
        context = decode_json(scenario.context_path.read_text())
        assert isinstance(context, dict)
        context["source_digest"] = source_digest(scenario.root)
        scenario.context_path.write_text(json.dumps(context))
        for suite in ("package", "ios-0", "ios-1"):
            directory = scenario.inputs / suite
            (directory / "source-inventory.json").write_text(json.dumps(sources))
            stamp_path = directory / "build-stamp.json"
            stamp = decode_json(stamp_path.read_text())
            assert isinstance(stamp, dict)
            stamp["identity"] = asdict(scenario.identity(suite))
            stamp["sources"] = sources
            stamp_path.write_text(json.dumps(stamp))
            scenario.reseal(suite)

        # when
        passed = scenario.aggregate()

        # then
        assert passed is True
        report = decode_json((scenario.output / "report.json").read_text())
        assert isinstance(report, dict)
        measurements = report.get("measurements")
        assert isinstance(measurements, dict)
        for scope in Scope:
            measurement = measurements[scope.value]
            assert isinstance(measurement, dict)
            mapped_sources = sources[1:2] if scope == Scope.PACKAGE else sources[:2]
            assert measurement.get("files") == mapped_sources
            assert measurement.get("unmapped_files") == [unmapped_source]
            assert set(mapped_sources) | {unmapped_source} == set(
                sources[1:] if scope == Scope.PACKAGE else sources
            )
            assert measurement.get("lines") == {"count": 2 * len(mapped_sources), "covered": 2 * len(mapped_sources)}
            assert measurement.get("regions") == {"count": 2 * len(mapped_sources), "covered": 2 * len(mapped_sources)}

    def test_given_approved_candidate_runtime_when_native_runtime_changes_then_rejects_before_coverage_math(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_aggregate import main
        from coverage_inventory import decode_json

        expected_runtime: JsonValue = {
            "architecture": "arm64",
            "model": "iPhone 17",
            "os_build": "23F77",
            "os_version": "26.5",
            "platform": "iOS Simulator",
        }
        exit_code = main(
            arguments=(
                "--candidate", "--context", str(scenario.context_path),
                "--inputs", str(scenario.inputs), "--output", str(scenario.output),
            ),
            executor=scenario.executor,
            root=scenario.root,
        )
        assert exit_code == 0
        candidate = decode_json((scenario.output / "candidate.json").read_text())
        assert isinstance(candidate, dict)
        assert candidate.get("ios_runtime") == expected_runtime
        candidate["passed"] = True
        candidate.pop("kind")
        scenario.baseline_path.write_text(json.dumps(candidate))
        assert scenario.aggregate() is True
        report = decode_json((scenario.output / "report.json").read_text())
        assert isinstance(report, dict)
        assert report.get("ios_runtime") == expected_runtime

        for suite in ("ios-0", "ios-1"):
            summary_path = scenario.inputs / suite / "test-summary.json"
            summary_path.write_text(
                summary_path.read_text().replace('"26.5"', '"26.6"').replace('"23F77"', '"23G80"')
            )
            scenario.reseal(suite)
        scenario.executor.commands.clear()

        # when
        with pytest.raises(ValueError, match="baseline.*runtime"):
            scenario.aggregate()

        # then
        assert scenario.executor.commands == []
        assert not (scenario.output / "report.json").exists()
        assert not (scenario.output / "report.html").exists()

    def test_given_ios_collections_listed_first_when_aggregated_then_total_keeps_host_first_mapping_counts(
        self: TestCoverageAggregate,
        monkeypatch: pytest.MonkeyPatch,
        scenario: AggregationScenario,
    ) -> None:
        """Total retains host-first overlap geometry; platform ratchets retain their own geometry."""
        # given
        from coverage_inventory import decode_json

        scenario.executor.order_dependent_total = True
        original_iterdir = Path.iterdir

        def ios_first_collections(path: Path) -> Iterator[Path]:
            if path == scenario.inputs:
                return iter(scenario.inputs / suite for suite in ("ios-1", "ios-0", "package"))
            return original_iterdir(path)

        monkeypatch.setattr(Path, "iterdir", ios_first_collections)
        original_profiles = {
            suite: (scenario.inputs / suite / "profile.profdata").read_bytes()
            for suite in ("package", "ios-0", "ios-1")
        }

        # when
        passed = scenario.aggregate()

        # then
        assert passed is True
        report = decode_json((scenario.output / "report.json").read_text())
        assert isinstance(report, dict)
        assert report.get("passed") is True
        measurements = report.get("measurements")
        assert isinstance(measurements, dict)
        total = measurements["aura-production-host-first-union-v1"]
        assert isinstance(total, dict)
        assert total.get("regions") == {"count": 4, "covered": 4}
        total_export = next(
            command for command in scenario.executor.commands
            if f"--instr-profile={scenario.output / 'total.profdata'}" in command
        )
        assert total_export[3] == str(scenario.inputs / "package/objects/Module")
        assert (scenario.output / "report.html").is_file()
        for suite, profile in original_profiles.items():
            assert (scenario.inputs / suite / "profile.profdata").read_bytes() == profile

    def test_given_raw_package_profile_when_aggregated_then_merges_into_output_before_package_export(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        raw_profile = scenario.inputs / "package/profile.profdata"
        original_profile = raw_profile.read_bytes()
        merged_profile = scenario.output / "package.profdata"
        expected_merge = (
            "xcrun", "llvm-profdata", "merge", "-sparse",
            str(raw_profile), "-o", str(merged_profile),
        )

        # when
        scenario.aggregate()

        # then
        commands = scenario.executor.commands
        assert expected_merge in commands, "Package export must consume a freshly merged raw profile"
        package_export = next(
            command for command in commands
            if command[1:3] == ("llvm-cov", "export")
            and str(scenario.inputs / "package/objects/Module") in command
            and "--empty-profile" not in command
        )
        assert f"--instr-profile={merged_profile}" in package_export
        assert commands.index(expected_merge) < commands.index(package_export)
        assert raw_profile.read_bytes() == original_profile

    def test_given_ios_shards_from_different_runtime_builds_when_aggregated_then_rejects_before_llvm(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_inventory import decode_json, ios_runtime_identity

        summary_path = scenario.inputs / "ios-1/test-summary.json"
        summary_path.write_text(
            summary_path.read_text()
            .replace('"osVersion": "26.5"', '"osVersion": "26.6"')
            .replace('"osBuildNumber": "23F77"', '"osBuildNumber": "23G100"')
        )
        runtime = ios_runtime_identity(decode_json(summary_path.read_text()))
        assert runtime.os_version == "26.6"
        scenario.reseal("ios-1")

        # when
        with pytest.raises(ValueError, match="runtime"):
            scenario.aggregate()

        # then
        assert scenario.executor.commands == []

    def test_given_valid_artifacts_when_candidate_is_measured_then_preserves_the_same_provenance_and_counters(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_aggregate import main
        from coverage_inventory import decode_json

        scenario.aggregate()
        reference = decode_json((scenario.output / "report.json").read_text())
        assert isinstance(reference, dict)
        expected_identity = decode_json(scenario.context_path.read_text())

        # when
        exit_code = main(
            arguments=(
                "--candidate", "--context", str(scenario.context_path),
                "--inputs", str(scenario.inputs), "--output", str(scenario.output),
            ),
            executor=scenario.executor,
            root=scenario.root,
        )

        # then
        assert exit_code == 0
        candidate = decode_json((scenario.output / "candidate.json").read_text())
        assert isinstance(candidate, dict)
        assert candidate.get("collection") == expected_identity
        assert candidate.get("measurements") == reference.get("measurements")

    def test_given_previous_passing_html_when_package_collection_is_missing_then_removes_the_stale_verdict(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        scenario.output.mkdir()
        report_path = scenario.output / "report.html"
        report_path.write_text("<html><body>PASSED: prior collection</body></html>")
        (scenario.inputs / "package").rename(scenario.root.parent / "missing-package")

        # when
        with pytest.raises(ValueError, match="missing required package coverage artifact"):
            scenario.aggregate()

        # then
        assert not report_path.exists(), "A failed collection must invalidate the previous passing HTML"
        assert scenario.executor.commands == []

    def test_given_valid_artifacts_when_aggregated_then_writes_the_passing_html_report(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        # when
        passed = scenario.aggregate()

        # then
        assert passed is True
        report_path = scenario.output / "report.html"
        assert report_path.is_file(), "Aggregation must emit the reviewable HTML coverage report"
        markup = report_path.read_text(encoding="utf-8")
        assert "PASSED" in markup
        assert "2/2" in markup
        assert "4/4" in markup
        for scope in Scope:
            assert scope.value in markup

    def test_given_valid_artifacts_when_reported_then_preserves_the_current_collection_identity(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_inventory import decode_json

        expected_identity = decode_json(scenario.context_path.read_text())

        # when
        scenario.aggregate()

        # then
        report = decode_json((scenario.output / "report.json").read_text())
        assert isinstance(report, dict)
        assert report.get("collection") == expected_identity

    def test_given_candidate_mode_when_cli_measures_then_emits_explicit_unevaluated_candidate(
        self: TestCoverageAggregate,
        capsys: pytest.CaptureFixture[str],
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_aggregate import main
        from coverage_inventory import decode_json
        # when
        exit_code = main(
            arguments=(
                "--candidate", "--context", str(scenario.context_path),
                "--inputs", str(scenario.inputs), "--output", str(scenario.output),
            ),
            executor=scenario.executor,
            root=scenario.root,
        )
        # then
        candidate = decode_json((scenario.output / "candidate.json").read_text())
        assert isinstance(candidate, dict)
        assert candidate.get("kind") == "baseline-candidate"
        assert candidate.get("passed") is None
        assert "ratchets" not in candidate
        assert exit_code == 0
        assert capsys.readouterr().out.strip() == "Candidate measurements only; ratchets not evaluated"
        assert not (scenario.output / "report.json").exists()

    def test_given_changed_checkout_when_aggregated_then_rejects_source_fingerprint(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given

        (scenario.root / "Aura/App.swift").write_text("struct Changed {}")
        # when
        with pytest.raises(ValueError, match="source fingerprint"):
            scenario.aggregate()
        # then
        assert scenario.executor.commands == []

    def test_given_unlinked_production_source_when_artifacts_are_self_consistent_then_rejects_missing_mapping_before_tools(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_inventory import decode_json

        unlinked_source = "AuraKit/Sources/Feature/Unlinked.swift"
        (scenario.root / unlinked_source).write_text("func unlinkedValue() -> Int { 42 }\n")
        sources = ["Aura/App.swift", "AuraKit/Sources/Feature/Domain.swift", unlinked_source]
        context = decode_json(scenario.context_path.read_text())
        assert isinstance(context, dict)
        context["source_digest"] = source_digest(scenario.root)
        scenario.context_path.write_text(json.dumps(context))
        for suite in ("package", "ios-0", "ios-1"):
            directory = scenario.inputs / suite
            (directory / "source-inventory.json").write_text(json.dumps(sources))
            stamp_path = directory / "build-stamp.json"
            stamp = decode_json(stamp_path.read_text())
            assert isinstance(stamp, dict)
            stamp["identity"] = asdict(scenario.identity(suite))
            stamp["sources"] = sources
            stamp_path.write_text(json.dumps(stamp))
            scenario.reseal(suite)

        # when
        with pytest.raises(ValueError, match="unclassified|missing.*mapping"):
            scenario.aggregate()

        # then
        assert scenario.executor.commands == []
        assert not (scenario.output / "report.json").exists()
        assert not (scenario.output / "report.html").exists()

    @pytest.mark.parametrize("suite", ["package", "ios-0", "ios-1"])
    def test_given_different_source_inventory_when_aggregated_then_rejects_before_tools(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
        suite: str,
    ) -> None:
        # given

        (scenario.inputs / suite / "source-inventory.json").write_text('["Aura/App.swift"]')
        scenario.reseal(suite)
        # when
        with pytest.raises(ValueError, match="source inventory"):
            scenario.aggregate()
        # then
        assert scenario.executor.commands == []

    def test_given_empty_inputs_when_cli_invoked_then_reports_missing_package_and_exits_nonzero(
        self: TestCoverageAggregate,
        tmp_path: Path,
    ) -> None:
        # given
        script = Path(__file__).with_name("coverage_aggregate.py")
        inputs = tmp_path / "inputs"
        inputs.mkdir()
        # when
        result = subprocess.run(
            (
                sys.executable, str(script), "--inputs", str(inputs), "--output", str(tmp_path / "output"),
                "--context", str(tmp_path / "context.json"), "--baseline", str(tmp_path / "baseline.json"),
            ),
            capture_output=True,
            text=True,
            timeout=10,
        )
        # then
        assert result.returncode != 0
        assert "missing required package coverage artifact" in result.stderr
        assert str(inputs) in result.stderr

    @pytest.mark.parametrize("suite", ["ios-0", "ios-1"])
    def test_given_failed_native_ios_receipt_when_aggregated_then_rejects_flat_success_lists(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
        suite: str,
    ) -> None:
        # given

        summary_path = scenario.inputs / suite / "test-summary.json"
        summary_path.write_text(summary_path.read_text().replace('"Passed"', '"Failed"'))
        scenario.reseal(suite)
        # when
        with pytest.raises(ValueError, match="summary result"):
            scenario.aggregate()
        # then
        assert scenario.executor.commands == []

    def test_given_failed_native_package_receipt_when_aggregated_then_rejects_flat_success_lists(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given

        events_path = scenario.inputs / "package/native-events.jsonl"
        events_path.write_text(events_path.read_text() + '\n{"kind":"event","payload":{"kind":"issueRecorded"},"version":0}')
        scenario.reseal("package")
        # when
        with pytest.raises(ValueError, match="failed or skipped"):
            scenario.aggregate()
        # then
        assert scenario.executor.commands == []

    def test_given_incomplete_ios_partition_when_aggregated_then_rejects_native_enumeration_gap(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given

        extra_method = '{"identifier": "AuraTests/C/c()"}'
        for suite in ("ios-0", "ios-1"):
            path = scenario.inputs / suite / "enumerated-tests.json"
            path.write_text(path.read_text().replace('{"identifier": "AuraTests/B/b()"}', '{"identifier": "AuraTests/B/b()"},' + extra_method))
            scenario.reseal(suite)
        # when
        with pytest.raises(ValueError, match="partition"):
            scenario.aggregate()
        # then
        assert scenario.executor.commands == []

    @pytest.mark.parametrize("field", ["identity", "objects", "platform", "schema", "sources"])
    def test_given_inconsistent_build_stamp_when_aggregated_then_rejects_compiled_inventory(
        self: TestCoverageAggregate,
        field: str,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_inventory import decode_json

        path = scenario.inputs / "package/build-stamp.json"
        stamp = decode_json(path.read_text())
        assert isinstance(stamp, dict)
        stamp[field] = None
        path.write_text(json.dumps(stamp))
        scenario.reseal("package")
        # when
        with pytest.raises(ValueError, match="build stamp"):
            scenario.aggregate()
        # then
        assert scenario.executor.commands == []

    def test_given_incomplete_mapping_receipt_when_aggregated_then_rejects_missing_mapping_before_tools(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_inventory import decode_json

        path = scenario.inputs / "package/build-stamp.json"
        stamp = decode_json(path.read_text())
        assert isinstance(stamp, dict)
        stamp["mapping_sources"] = ["Aura/App.swift"]
        path.write_text(json.dumps(stamp))
        scenario.reseal("package")
        # when
        with pytest.raises(ValueError, match="missing LLVM mapping"):
            scenario.aggregate()
        # then
        assert scenario.executor.commands == []

    def test_given_missing_package_test_binary_when_aggregated_then_rejects_mapping_inventory(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_inventory import decode_json

        directory = scenario.inputs / "package"
        (directory / "objects/Module").rename(directory / "objects/Other")
        stamp_path = directory / "build-stamp.json"
        stamp = decode_json(stamp_path.read_text())
        assert isinstance(stamp, dict)
        stamp["objects"] = ["objects/Other"]
        stamp_path.write_text(json.dumps(stamp))
        scenario.reseal("package")
        # when
        with pytest.raises(ValueError, match="package test target"):
            scenario.aggregate()
        # then
        assert scenario.executor.commands == []

    def test_given_no_package_artifact_when_aggregated_then_fails_before_tool_execution(
        self: TestCoverageAggregate,
        tmp_path: Path,
    ) -> None:
        # given

        inputs = tmp_path / "inputs"
        inputs.mkdir()
        # when
        with pytest.raises(ValueError, match="missing required package coverage artifact"):
            aggregate(
                baseline_path=tmp_path / "baseline.json",
                context_path=tmp_path / "context.json",
                inputs=inputs,
                output=tmp_path / "output",
            )
        # then

    def test_given_previous_success_report_when_new_aggregation_fails_then_invalidates_old_verdict(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        scenario.output.mkdir()
        report_path = scenario.output / "report.json"
        report_path.write_text('{"passed":true}')
        (scenario.root / "Aura/App.swift").write_text("struct Changed {}")
        # when
        with pytest.raises(ValueError, match="source fingerprint"):
            scenario.aggregate()
        # then
        assert not report_path.exists()

    def test_given_recorded_runner_paths_when_aggregated_then_normalizes_and_retains_raw_exports(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given

        scenario.executor.recorded_roots = True
        # when
        passed = scenario.aggregate()
        # then
        assert passed is True
        raw_export = scenario.output / f"{Scope.PACKAGE.value}.json"
        assert "/runner/package/AuraKit" in raw_export.read_text()

    def test_given_shared_package_test_bundle_when_aggregated_then_requires_explicit_native_targets(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_inventory import decode_json

        directory = scenario.inputs / "package"
        (directory / "objects/Module").rename(directory / "objects/AuraKitPackageTests")
        stamp_path = directory / "build-stamp.json"
        stamp = decode_json(stamp_path.read_text())
        assert isinstance(stamp, dict)
        stamp["objects"] = ["objects/AuraKitPackageTests"]
        stamp["package_test_targets"] = ["Module"]
        stamp_path.write_text(json.dumps(stamp))
        scenario.reseal("package")
        # when
        passed = scenario.aggregate()
        # then
        assert passed is True

    def test_given_successful_command_with_stderr_when_executed_then_rejects_llvm_diagnostic(
        self: TestCoverageAggregate,
    ) -> None:
        # given
        from coverage_aggregate import SubprocessExecutor

        command = (sys.executable, "-c", "import sys; print('mapping warning', file=sys.stderr)")
        # when
        with pytest.raises(ValueError, match="LLVM diagnostic.*mapping warning"):
            SubprocessExecutor().execute(command)
        # then

    def test_given_valid_artifacts_when_aggregated_then_merges_profiles_before_three_exports(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        raw_profiles = {
            suite: scenario.inputs / suite / "profile.profdata"
            for suite in ("package", "ios-0", "ios-1")
        }
        original_profiles = {suite: path.read_bytes() for suite, path in raw_profiles.items()}
        expected_inputs = {
            str(scenario.output / "ios.profdata"): (raw_profiles["ios-0"], raw_profiles["ios-1"]),
            str(scenario.output / "package.profdata"): (raw_profiles["package"],),
            str(scenario.output / "total.profdata"): tuple(raw_profiles.values()),
        }
        # when
        passed = scenario.aggregate()
        # then
        assert passed is True
        commands = scenario.executor.commands
        mapping_exports = [command for command in commands if "--empty-profile" in command]
        merges = [command for command in commands if command[1:3] == ("llvm-profdata", "merge")]
        measured_exports = [
            command for command in commands
            if any(argument.startswith("--instr-profile=") for argument in command)
        ]
        assert len(mapping_exports) == 3
        assert len(merges) == 3
        assert {
            command[command.index("-o") + 1]
            for command in merges
        } == set(expected_inputs)
        for command in merges:
            output_index = command.index("-o")
            inputs = command[4:output_index]
            expected = expected_inputs[command[output_index + 1]]
            assert command[:4] == ("xcrun", "llvm-profdata", "merge", "-sparse")
            assert len(inputs) == len(expected)
            assert set(inputs) == {str(path) for path in expected}
        assert max(commands.index(command) for command in mapping_exports) < min(
            commands.index(command) for command in merges
        )
        assert max(commands.index(command) for command in merges) < min(
            commands.index(command) for command in measured_exports
        )
        assert {
            argument.split("=", 1)[1]
            for command in measured_exports
            for argument in command
            if argument.startswith("--instr-profile=")
        } == set(expected_inputs)
        for profile in expected_inputs:
            scope_exports = [
                command for command in measured_exports
                if f"--instr-profile={profile}" in command
            ]
            assert len(scope_exports) == 2
            object_orders = [
                (command[3], *(
                    argument.split("=", 1)[1]
                    for argument in command
                    if argument.startswith("--object=")
                ))
                for command in scope_exports
            ]
            assert object_orders[1] == tuple(reversed(object_orders[0]))
        assert all(
            command[:2] in {("xcrun", "llvm-cov"), ("xcrun", "llvm-profdata")}
            for command in commands
        )
        for suite, profile in raw_profiles.items():
            assert profile.read_bytes() == original_profiles[suite]
        assert (scenario.output / "report.json").is_file()

    def test_given_valid_artifacts_when_measured_without_baseline_then_returns_no_gate_verdict(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_aggregate import measure_artifacts
        # when
        identity, measurements, runtime = measure_artifacts(
            context_path=scenario.context_path,
            executor=scenario.executor,
            inputs=scenario.inputs,
            output=scenario.output,
            root=scenario.root,
        )
        # then
        assert set(measurements) == set(Scope)
        assert identity.toolchain == "Xcode 26"
        assert not (scenario.output / "report.json").exists()

    def test_given_valid_measurements_when_aggregated_then_writes_all_six_ratchet_verdicts(
        self: TestCoverageAggregate,
        scenario: AggregationScenario,
    ) -> None:
        # given
        from coverage_inventory import decode_json
        # when
        scenario.aggregate()
        # then
        report = decode_json((scenario.output / "report.json").read_text())
        assert isinstance(report, dict)
        verdicts = report.get("ratchets")
        assert isinstance(verdicts, list)
        assert len(verdicts) == 6
        assert report.get("schema") == 1

    @pytest.mark.parametrize("collections", [("package",), ("package", "ios-0"), ("package", "ios-0", "ios-1", "extra")])
    def test_given_wrong_collection_inventory_when_aggregated_then_rejects_before_tools(
        self: TestCoverageAggregate,
        collections: tuple[str, ...],
        tmp_path: Path,
    ) -> None:
        # given

        inputs = tmp_path / "inputs"
        for name in collections:
            directory = inputs / name
            directory.mkdir(parents=True)
            (directory / "manifest.json").write_text("{}")
        # when
        with pytest.raises(ValueError, match="collection inventory"):
            aggregate(
                baseline_path=tmp_path / "baseline.json",
                context_path=tmp_path / "context.json",
                inputs=inputs,
                output=tmp_path / "output",
            )
        # then
