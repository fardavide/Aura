from __future__ import annotations

from dataclasses import dataclass
import json
from pathlib import Path

import pytest
import yaml

from coverage_inventory import JsonValue, decode_json


@dataclass(frozen=True)
class WorkflowScenario:
    document: dict[str, JsonValue]

    def commands(self: WorkflowScenario, name: str) -> tuple[str, ...]:
        return tuple(
            command
            for step in self.steps(name)
            if isinstance(command := step.get("run"), str)
        )

    def job(self: WorkflowScenario, name: str) -> dict[str, JsonValue]:
        jobs = self.document.get("jobs")
        assert isinstance(jobs, dict)
        job = jobs.get(name)
        assert isinstance(job, dict), f"missing workflow job: {name}"
        return job

    def steps(self: WorkflowScenario, name: str) -> tuple[dict[str, JsonValue], ...]:
        entries = self.job(name).get("steps")
        assert isinstance(entries, list)
        result: list[dict[str, JsonValue]] = []
        for entry in entries:
            assert isinstance(entry, dict)
            result.append(entry)
        return tuple(result)


@pytest.fixture
def workflow() -> WorkflowScenario:
    path = Path(__file__).resolve().parents[1] / "workflows/ci.yml"
    loaded: object = yaml.load(path.read_text(), Loader=yaml.BaseLoader)
    document = decode_json(json.dumps(loaded))
    assert isinstance(document, dict)
    return WorkflowScenario(document=document)


class TestCoverageWorkflow:
    def test_given_application_reference_input_when_candidate_runs_then_passes_reference_through_environment_with_parent_history(
        self: TestCoverageWorkflow,
        workflow: WorkflowScenario,
    ) -> None:
        # given
        triggers = workflow.document.get("on")
        assert isinstance(triggers, dict)
        dispatch = triggers.get("workflow_dispatch")
        assert isinstance(dispatch, dict)
        inputs = dispatch.get("inputs")
        assert isinstance(inputs, dict)

        # when
        steps = workflow.steps("coverage-candidate")
        commands = workflow.commands("coverage-candidate")

        # then
        application_reference = inputs.get("application_reference")
        assert isinstance(application_reference, dict), "Candidate dispatch needs an application reference input"
        assert application_reference.get("type") == "string"
        checkout = next(step for step in steps if step.get("uses") == "actions/checkout@v4")
        checkout_settings = checkout.get("with")
        assert isinstance(checkout_settings, dict)
        assert checkout_settings.get("fetch-depth") == "2"
        candidate = next(step for step in steps if step.get("run") == "make coverage-candidate")
        environment = candidate.get("env")
        assert isinstance(environment, dict)
        assert environment.get("AURA_COVERAGE_APPLICATION_REFERENCE") == "${{ inputs.application_reference }}"
        assert all("inputs.application_reference" not in command for command in commands)

    def test_given_build_matrix_when_executed_then_reuses_ios_products_and_preserves_macos_compile(
        self: TestCoverageWorkflow,
        workflow: WorkflowScenario,
    ) -> None:
        # given
        build = workflow.job("build")
        strategy = build.get("strategy")
        assert isinstance(strategy, dict)
        matrix = strategy.get("matrix")
        assert isinstance(matrix, dict)
        platforms = matrix.get("platform")
        assert isinstance(platforms, list)
        steps = workflow.steps("build")
        ios = tuple(step for step in steps if "matrix.platform.name == 'iOS'" in str(step.get("if")))
        macos = tuple(step for step in steps if "matrix.platform.name == 'macOS'" in str(step.get("if")))
        # when
        # then
        assert {platform["name"] for platform in platforms if isinstance(platform, dict)} == {"iOS", "macOS"}
        ios_commands = tuple(step["run"] for step in ios if "run" in step)
        assert "make coverage-ios-build" in ios_commands
        assert "make coverage-products" in ios_commands
        assert ios_commands.index("make coverage-ios-build") < ios_commands.index("make coverage-products")
        products = next(step for step in ios if step.get("uses") == "actions/upload-artifact@v4")
        upload = products.get("with")
        assert isinstance(upload, dict)
        assert upload.get("name") == "ios-test-products"
        assert set(str(upload.get("path")).splitlines()) == {
            "build/coverage-context.json", "build/ios-products.json", "build/ios-products.tar.gz",
        }
        cache = next(step for step in ios if step.get("uses") == "actions/cache@v4")
        cache_settings = cache.get("with")
        assert isinstance(cache_settings, dict)
        assert cache_settings.get("path") == "SourcePackages"
        macos_commands = tuple(str(step["run"]) for step in macos if "run" in step)
        assert len(macos_commands) == 1
        assert macos_commands[0].startswith("xcodebuild build")
        assert "-jobs 4" in macos_commands[0]
        assert "generic/platform=macOS" in macos_commands[0]

    def test_given_coverage_gate_when_collections_finish_then_aggregates_and_ratchets_without_native_execution(
        self: TestCoverageWorkflow,
        workflow: WorkflowScenario,
    ) -> None:
        # given
        job = workflow.job("coverage")
        commands = workflow.commands("coverage")
        steps = workflow.steps("coverage")
        # when
        # then
        assert job.get("name") == "Coverage"
        assert job.get("runs-on") == "macos-26"
        needs = job.get("needs")
        assert isinstance(needs, list)
        assert set(needs) == {"unit-tests", "build", "snapshot-tests"}
        assert job.get("if") in ("always()", "${{ always() }}")
        guard = next(command for command in commands if "exit 1" in command)
        assert all(f"needs.{name}.result" in guard for name in needs)
        assert "success" in guard
        permissions = job.get("permissions", workflow.document.get("permissions"))
        assert isinstance(permissions, dict)
        assert permissions.get("actions") == "read"
        assert permissions.get("contents") == "read"
        downloads: dict[str, str] = {}
        for step in steps:
            if step.get("uses") == "actions/download-artifact@v4":
                settings = step.get("with")
                assert isinstance(settings, dict)
                name = settings.get("name")
                path = settings.get("path")
                assert isinstance(name, str)
                assert isinstance(path, str)
                downloads[name] = path
        assert downloads == {
            "coverage-ios-0": "build/coverage-inputs/ios-0",
            "coverage-ios-1": "build/coverage-inputs/ios-1",
            "coverage-package": "build/coverage-inputs/package",
        }
        assert any(step.get("uses") == "./.github/actions/select-xcode" for step in steps)
        assert commands.count("make coverage-report") == 1
        assert commands.index("make coverage-context") < commands.index("make coverage-baseline-fetch")
        assert commands.index("make coverage-baseline-fetch") < commands.index("make coverage-report")
        fetch = next(step for step in steps if step.get("run") == "make coverage-baseline-fetch")
        environment = fetch.get("env")
        assert isinstance(environment, dict)
        assert environment.get("GH_TOKEN") == "${{ github.token }}"
        uploads: dict[str, dict[str, JsonValue]] = {}
        for step in steps:
            settings = step.get("with")
            if step.get("uses") == "actions/upload-artifact@v4" and isinstance(settings, dict):
                name = settings.get("name")
                assert isinstance(name, str)
                uploads[name] = step
        baseline = uploads["coverage-baseline"]
        condition = baseline.get("if")
        assert isinstance(condition, str)
        assert all(fragment in condition for fragment in ("success()", "github.event_name == 'push'", "github.ref == 'refs/heads/main'"))
        report = uploads["coverage-report"]
        assert report.get("if") in ("always()", "${{ always() }}")
        report_settings = report.get("with")
        assert isinstance(report_settings, dict)
        assert "build/coverage" in str(report_settings.get("path"))
        assert not any(
            "xcodebuild test" in command or "xcodebuild build" in command
            or "make coverage-package" in command or "make coverage-ios" in command
            or "swift test" in command
            for command in commands
        )

    def test_given_manual_candidate_request_when_collected_then_keeps_measurements_separate_from_required_ratchets(
        self: TestCoverageWorkflow,
        workflow: WorkflowScenario,
    ) -> None:
        # given
        triggers = workflow.document.get("on")
        assert isinstance(triggers, dict)
        dispatch = triggers.get("workflow_dispatch")
        assert isinstance(dispatch, dict)
        inputs = dispatch.get("inputs")
        assert isinstance(inputs, dict)
        candidate_input = inputs.get("baseline_candidate")
        assert isinstance(candidate_input, dict)
        job = workflow.job("coverage-candidate")
        commands = workflow.commands("coverage-candidate")
        steps = workflow.steps("coverage-candidate")
        # when
        # then
        assert candidate_input.get("type") == "boolean"
        assert candidate_input.get("default") == "false"
        assert job.get("name") == "Coverage candidate"
        assert job.get("runs-on") == "macos-26"
        needs = job.get("needs")
        assert isinstance(needs, list)
        assert set(needs) == {"unit-tests", "build", "snapshot-tests"}
        condition = job.get("if")
        assert isinstance(condition, str)
        assert "always()" in condition
        assert "github.event_name == 'workflow_dispatch'" in condition
        assert "inputs.baseline_candidate" in condition
        guard = next(command for command in commands if "exit 1" in command)
        assert all(f"needs.{name}.result" in guard for name in needs)
        assert "success" in guard
        downloads: dict[str, str] = {}
        for step in steps:
            if step.get("uses") == "actions/download-artifact@v4":
                settings = step.get("with")
                assert isinstance(settings, dict)
                name = settings.get("name")
                path = settings.get("path")
                assert isinstance(name, str)
                assert isinstance(path, str)
                downloads[name] = path
        assert downloads == {
            "coverage-ios-0": "build/coverage-inputs/ios-0",
            "coverage-ios-1": "build/coverage-inputs/ios-1",
            "coverage-package": "build/coverage-inputs/package",
        }
        assert commands.count("make coverage-candidate") == 1
        assert commands.index("make coverage-context") < commands.index("make coverage-candidate")
        assert "make coverage-baseline-fetch" not in commands
        assert "make coverage-report" not in commands
        uploads = tuple(step for step in steps if step.get("uses") == "actions/upload-artifact@v4")
        assert len(uploads) == 1
        candidate_upload = uploads[0].get("with")
        assert isinstance(candidate_upload, dict)
        assert candidate_upload.get("name") == "coverage-candidate-report"
        assert "candidate.json" in str(candidate_upload.get("path"))
        assert candidate_upload.get("overwrite", "false") == "false"
        assert workflow.job("coverage").get("if") in ("always()", "${{ always() }}")
        assert workflow.commands("coverage").count("make coverage-report") == 1

    def test_given_snapshot_gate_when_shards_finish_then_validates_receipts_without_native_execution(
        self: TestCoverageWorkflow,
        workflow: WorkflowScenario,
    ) -> None:
        # given
        job = workflow.job("snapshot-tests")
        commands = workflow.commands("snapshot-tests")
        steps = workflow.steps("snapshot-tests")
        # when
        # then
        assert job.get("name") == "Snapshot tests (iOS)"
        assert job.get("runs-on") == "ubuntu-latest"
        assert job.get("needs") in ("snapshot-shards", ["snapshot-shards"])
        assert job.get("if") in ("always()", "${{ always() }}")
        assert any(
            "needs.snapshot-shards.result" in command
            and "success" in command
            and "exit 1" in command
            for command in commands
        )
        downloads: dict[str, str] = {}
        for step in steps:
            if step.get("uses") == "actions/download-artifact@v4":
                settings = step.get("with")
                assert isinstance(settings, dict)
                name = settings.get("name")
                path = settings.get("path")
                assert isinstance(name, str)
                assert isinstance(path, str)
                downloads[name] = path
        assert downloads == {
            "coverage-ios-0": "build/coverage-inputs/ios-0",
            "coverage-ios-1": "build/coverage-inputs/ios-1",
        }
        verification = "python3 .github/scripts/coverage_collect.py verify-ios --inputs build/coverage-inputs --context build/coverage-context.json"
        assert commands.count(verification) == 1
        assert not any(
            "xcodebuild" in command or "make coverage-ios" in command or "swift test" in command
            for command in commands
        )

    def test_given_snapshot_shards_when_executed_then_reuses_products_on_isolated_runners(
        self: TestCoverageWorkflow,
        workflow: WorkflowScenario,
    ) -> None:
        # given
        job = workflow.job("snapshot-shards")
        strategy = job.get("strategy")
        assert isinstance(strategy, dict)
        matrix = strategy.get("matrix")
        assert isinstance(matrix, dict)
        steps = workflow.steps("snapshot-shards")
        commands = workflow.commands("snapshot-shards")
        # when
        # then
        assert matrix.get("shard") == ["0", "1"]
        assert strategy.get("fail-fast") == "false"
        assert job.get("runs-on") == "macos-26"
        assert job.get("needs") in ("build", ["build"])
        collection = "make coverage-ios SHARD=${{ matrix.shard }}"
        assert commands.count(collection) == 1
        assert commands.index("make coverage-context") < commands.index("make coverage-products-restore")
        assert commands.index("make coverage-products-restore") < commands.index(collection)
        assert not any("xcodebuild test" in command or "xcodebuild build" in command for command in commands)
        download = next(step for step in steps if step.get("uses") == "actions/download-artifact@v4")
        download_settings = download.get("with")
        assert isinstance(download_settings, dict)
        assert download_settings.get("name") == "ios-test-products"
        assert download_settings.get("path") == "build"
        uploads: dict[str, dict[str, JsonValue]] = {}
        for step in steps:
            settings = step.get("with")
            if step.get("uses") == "actions/upload-artifact@v4" and isinstance(settings, dict):
                name = settings.get("name")
                assert isinstance(name, str)
                uploads[name] = step
        coverage = uploads["coverage-ios-${{ matrix.shard }}"]
        coverage_settings = coverage.get("with")
        assert isinstance(coverage_settings, dict)
        assert coverage_settings.get("path") == "build/coverage-inputs/ios-${{ matrix.shard }}"
        assert coverage.get("if") in ("always()", "${{ always() }}")
        for name, path in (
            ("snapshot-diffs-${{ matrix.shard }}", "snapshot-report"),
            ("snapshot-results-${{ matrix.shard }}", "build/coverage-diagnostics/ios-${{ matrix.shard }}.xcresult"),
        ):
            diagnostic = uploads[name]
            settings = diagnostic.get("with")
            assert isinstance(settings, dict)
            assert settings.get("path") == path
            assert diagnostic.get("if") in ("failure()", "${{ failure() }}")
        assert any(
            ".github/scripts/snapshot-report.py" in command
            and "AuraTests/__SnapshotFailures__" in command
            and "AuraTests/__Snapshots__" in command
            for command in commands
        )

    def test_given_tooling_job_when_executed_then_runs_fast_python_checks_without_native_work(
        self: TestCoverageWorkflow,
        workflow: WorkflowScenario,
    ) -> None:
        # given
        job = workflow.job("coverage-tooling-tests")
        commands = workflow.commands("coverage-tooling-tests")
        steps = workflow.steps("coverage-tooling-tests")
        # when
        # then
        assert job.get("runs-on") == "ubuntu-latest"
        assert any(step.get("uses") == "actions/checkout@v4" for step in steps)
        assert any("python3 -m venv" in command for command in commands)
        assert any(
            "pip install" in command and "-r .github/scripts/requirements-coverage.txt" in command
            for command in commands
        )
        assert sum("make coverage-tests" in command for command in commands) == 1
        requirements = Path(__file__).parent / "requirements-coverage.txt"
        assert set(requirements.read_text().splitlines()) == {"pytest==9.1.1", "PyYAML==6.0.3"}
        assert not any(
            "xcodebuild" in command or "swift test" in command
            or "make coverage-package" in command or "make coverage-ios" in command
            for command in commands
        )

    def test_given_unit_job_when_executed_then_collects_package_coverage_once(
        self: TestCoverageWorkflow,
        workflow: WorkflowScenario,
    ) -> None:
        # given
        commands = workflow.commands("unit-tests")
        # when
        # then
        assert commands.count("make coverage-package") == 1
        assert not any(command.startswith("swift test") for command in commands)
