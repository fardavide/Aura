from __future__ import annotations

from dataclasses import dataclass, field
import json
from pathlib import Path
import sys

import pytest

from coverage_inventory import JsonValue, decode_json


@dataclass
class FakeExecutor:
    responses: list[str] = field(default_factory=list)
    commands: list[tuple[str, ...]] = field(default_factory=list)
    downloaded_report: JsonValue = None

    def execute(self: FakeExecutor, command: tuple[str, ...]) -> str:
        self.commands.append(command)
        if command[:3] == ("gh", "run", "download"):
            directory = Path(command[command.index("--dir") + 1])
            (directory / "report.json").write_text(json.dumps(self.downloaded_report))
        return self.responses.pop(0)


@pytest.fixture
def run() -> dict[str, JsonValue]:
    return {"conclusion": "success", "databaseId": 12, "headSha": "a" * 40, "event": "push", "createdAt": "2026-10-02T10:00:00Z", "workflowName": "CI"}


@pytest.fixture
def view() -> dict[str, JsonValue]:
    return {"conclusion": "success", "headSha": "a" * 40, "event": "push", "jobs": [
        {"name": name, "conclusion": "success"} for name in ("Unit tests (AuraKit)", "Build app (iOS)", "Build app (macOS)", "Snapshot tests (iOS)")
    ]}


@pytest.fixture
def approved_seed(tmp_path: Path) -> Path:
    path = tmp_path / "seed.json"
    path.write_text(json.dumps({"approved": True, "kind": "approved-initial-baseline", "passed": True, "schema": 1, "source_revision": "a" * 40, "toolchain": "Xcode 26.6"}))
    return path


@pytest.fixture
def api_run() -> dict[str, JsonValue]:
    return {"id": 12, "head_sha": "a" * 40, "head_branch": "main", "event": "push", "conclusion": "success", "status": "completed", "run_attempt": 2}


@pytest.fixture
def artifact_report() -> dict[str, JsonValue]:
    return {"collection": {"revision": "a" * 40, "run": "github:12:2"}, "schema": 1, "passed": True, "toolchain": "Xcode 26.6"}


@pytest.fixture
def artifacts() -> dict[str, JsonValue]:
    return {"total_count": 1, "artifacts": [{"id": 7, "name": "coverage-baseline", "expired": False}]}


class TestCoverageBaseline:
    def test_given_missing_initial_seed_when_cli_fetches_then_review_action_is_reported(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], capsys: pytest.CaptureFixture[str]) -> None:
        # Given
        from coverage_baseline import main

        output = tmp_path / "report.json"
        output.write_text('{"passed":true}')
        executor = FakeExecutor(responses=[json.dumps([run]), json.dumps(view)])

        # When
        result = main(("--output", str(output), "--seed", str(tmp_path / "missing.json")), executor)

        # Then
        assert result == 1
        assert "review candidate measurements" in capsys.readouterr().err
        assert not output.exists()

    def test_given_default_cli_arguments_when_fetched_then_default_paths_and_executor_are_used(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], approved_seed: Path, monkeypatch: pytest.MonkeyPatch) -> None:
        # Given
        import coverage_baseline

        monkeypatch.chdir(tmp_path)
        seed = tmp_path / ".github" / "coverage" / "baseline.json"
        seed.parent.mkdir(parents=True)
        approved_seed.replace(seed)
        executor = FakeExecutor(responses=[json.dumps([run]), json.dumps(view)])
        monkeypatch.setattr(coverage_baseline, "SubprocessExecutor", lambda: executor)

        # When
        result = coverage_baseline.main(())

        # Then
        assert result == 0
        assert (tmp_path / ".coverage-baseline" / "report.json").read_bytes() == seed.read_bytes()
        assert executor.commands[0][3:5] == ("--repo", "fardavide/Aura")

    def test_given_failed_command_when_executed_then_error_includes_diagnostic(self: TestCoverageBaseline) -> None:
        # Given
        from coverage_baseline import SubprocessExecutor

        executor = SubprocessExecutor()

        # When
        with pytest.raises(ValueError, match="exit 2: permission denied"):
            executor.execute((sys.executable, "-c", "import sys; print('permission denied', file=sys.stderr); sys.exit(2)"))

        # Then
        # No stdout is accepted as a successful fetch.

    def test_given_successful_command_when_executed_then_stdout_is_captured(self: TestCoverageBaseline) -> None:
        # Given
        from coverage_baseline import SubprocessExecutor

        executor = SubprocessExecutor()

        # When
        output = executor.execute((sys.executable, "-c", "print('native-command-result')"))

        # Then
        assert output == "native-command-result\n"

    def test_given_cli_fetch_when_seed_is_approved_then_report_is_written(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], approved_seed: Path) -> None:
        # Given
        from coverage_baseline import main

        executor = FakeExecutor(responses=[json.dumps([run]), json.dumps(view)])
        output = tmp_path / "report.json"

        # When
        result = main(("--repo", "fardavide/Aura", "--output", str(output), "--seed", str(approved_seed)), executor)

        # Then
        assert result == 0
        assert output.read_bytes() == approved_seed.read_bytes()

    @pytest.mark.parametrize(("field_name", "value"), [("schema", True), ("schema", 2), ("passed", None), ("passed", False), ("toolchain", ""), ("collection", None), ("revision", "b" * 40), ("run", "github:12:1"), ("run", "github:13:2")])
    def test_given_downloaded_report_without_matching_success_when_fetched_then_seed_fallback_is_forbidden(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], api_run: dict[str, JsonValue], artifacts: dict[str, JsonValue], artifact_report: dict[str, JsonValue], approved_seed: Path, field_name: str, value: JsonValue) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        jobs = view["jobs"]
        assert isinstance(jobs, list)
        jobs.append({"name": "Coverage", "conclusion": "success"})
        if field_name in ("revision", "run"):
            collection = artifact_report["collection"]
            assert isinstance(collection, dict)
            collection[field_name] = value
        else:
            artifact_report[field_name] = value
        output = tmp_path / "report.json"
        executor = FakeExecutor(responses=[json.dumps([run]), json.dumps(view), json.dumps(artifacts), json.dumps(api_run), ""], downloaded_report=artifact_report)

        # When
        with pytest.raises(ValueError, match="baseline report"):
            fetch_baseline("fardavide/Aura", output, approved_seed, executor)

        # Then
        assert not output.exists()

    @pytest.mark.parametrize(("field_name", "value"), [("id", 13), ("id", 12.0), ("head_sha", "b" * 40), ("head_branch", "feature"), ("event", "pull_request"), ("conclusion", "failure"), ("status", "in_progress"), ("run_attempt", 0), ("run_attempt", True), ("run_attempt", None)])
    def test_given_api_run_identity_mismatch_when_fetched_then_download_is_rejected(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], api_run: dict[str, JsonValue], artifacts: dict[str, JsonValue], artifact_report: dict[str, JsonValue], approved_seed: Path, field_name: str, value: JsonValue) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        jobs = view["jobs"]
        assert isinstance(jobs, list)
        jobs.append({"name": "Coverage", "conclusion": "success"})
        api_run[field_name] = value
        executor = FakeExecutor(responses=[json.dumps([run]), json.dumps(view), json.dumps(artifacts), json.dumps(api_run), ""], downloaded_report=artifact_report)

        # When
        with pytest.raises(ValueError, match="CI run identity"):
            fetch_baseline("fardavide/Aura", tmp_path / "report.json", approved_seed, executor)

        # Then
        assert not (tmp_path / "report.json").exists()
        assert all(command[:3] != ("gh", "run", "download") for command in executor.commands)

    @pytest.mark.parametrize("state", ["missing", "expired", "duplicate", "unknown-expiry", "invalid-id", "incomplete-list"])
    def test_given_invalid_coverage_artifact_when_fetched_then_seed_fallback_is_forbidden(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], api_run: dict[str, JsonValue], artifacts: dict[str, JsonValue], artifact_report: dict[str, JsonValue], approved_seed: Path, state: str) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        jobs = view["jobs"]
        assert isinstance(jobs, list)
        jobs.append({"name": "Coverage", "conclusion": "success"})
        values = artifacts["artifacts"]
        assert isinstance(values, list)
        value = values[0]
        assert isinstance(value, dict)
        if state == "missing":
            value["name"] = "other"
        elif state == "duplicate":
            values.append({**value, "id": 8})
            artifacts["total_count"] = 2
        elif state == "incomplete-list":
            artifacts["total_count"] = 2
        elif state == "invalid-id":
            value["id"] = True
        else:
            value["expired"] = True if state == "expired" else None
        output = tmp_path / "report.json"
        executor = FakeExecutor(responses=[json.dumps([run]), json.dumps(view), json.dumps(artifacts), json.dumps(api_run), ""], downloaded_report=artifact_report)

        # When
        with pytest.raises(ValueError, match="artifact"):
            fetch_baseline("fardavide/Aura", output, approved_seed, executor)

        # Then
        assert not output.exists()
        assert all(command[:3] != ("gh", "run", "download") for command in executor.commands)

    def test_given_green_coverage_run_when_fetched_then_exact_run_artifact_is_used(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], api_run: dict[str, JsonValue], artifacts: dict[str, JsonValue], artifact_report: dict[str, JsonValue]) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        jobs = view["jobs"]
        assert isinstance(jobs, list)
        jobs.append({"name": "Coverage", "conclusion": "success"})
        executor = FakeExecutor(responses=[json.dumps([run]), json.dumps(view), json.dumps(artifacts), json.dumps(api_run), ""], downloaded_report=artifact_report)
        output = tmp_path / "baseline" / "report.json"

        # When
        fetch_baseline("fardavide/Aura", output, tmp_path / "no-seed.json", executor)

        # Then
        assert decode_json(output.read_text()) == artifact_report
        assert executor.commands[2] == ("gh", "api", "repos/fardavide/Aura/actions/runs/12/artifacts")
        assert executor.commands[3] == ("gh", "api", "repos/fardavide/Aura/actions/runs/12")
        assert executor.commands[4][:8] == ("gh", "run", "download", "12", "--repo", "fardavide/Aura", "--name", "coverage-baseline")

    @pytest.mark.parametrize(("field_name", "value"), [("conclusion", "failure"), ("event", "pull_request"), ("headSha", "b" * 40)])
    def test_given_run_view_disagrees_when_fetched_then_identity_is_rejected(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], approved_seed: Path, field_name: str, value: JsonValue) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        view[field_name] = value

        # When
        with pytest.raises(ValueError, match="CI run"):
            fetch_baseline("fardavide/Aura", tmp_path / "report.json", approved_seed, FakeExecutor(responses=[json.dumps([run]), json.dumps(view)]))

        # Then
        assert not (tmp_path / "report.json").exists()

    def test_given_newest_run_lacks_required_job_when_fetched_then_previous_fully_green_run_is_selected(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], approved_seed: Path) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        newest = {**run, "databaseId": 13, "createdAt": "2026-10-02T11:00:00Z"}
        executor = FakeExecutor(responses=[json.dumps([run, newest]), json.dumps({**view, "jobs": []}), json.dumps(view)])

        # When
        fetch_baseline("fardavide/Aura", tmp_path / "report.json", approved_seed, executor)

        # Then
        assert [command[3] for command in executor.commands[1:]] == ["13", "12"]

    @pytest.mark.parametrize("state", ["missing", "failure", "skipped", "duplicate", "coverage-failure"])
    def test_given_required_context_not_green_when_fetched_then_run_is_rejected(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], approved_seed: Path, state: str) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        jobs = view["jobs"]
        assert isinstance(jobs, list)
        if state == "missing":
            jobs.pop()
        elif state == "duplicate":
            jobs.append(jobs[0])
        elif state == "coverage-failure":
            jobs.append({"name": "Coverage", "conclusion": "failure"})
        else:
            job = jobs[0]
            assert isinstance(job, dict)
            job["conclusion"] = state
        output = tmp_path / "report.json"

        # When
        with pytest.raises(ValueError, match="fully green"):
            fetch_baseline("fardavide/Aura", output, approved_seed, FakeExecutor(responses=[json.dumps([run]), json.dumps(view)]))

        # Then
        assert not output.exists()

    @pytest.mark.parametrize(("field_name", "value"), [("conclusion", "failure"), ("event", "pull_request"), ("workflowName", "Other"), ("databaseId", True), ("databaseId", 0), ("headSha", "short"), ("createdAt", "2026-10-02T10:00:00")])
    def test_given_ineligible_run_when_fetched_then_no_baseline_is_generated(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], approved_seed: Path, field_name: str, value: JsonValue) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        run[field_name] = value
        output = tmp_path / "report.json"

        # When
        with pytest.raises(ValueError, match="CI run|fully green"):
            fetch_baseline("fardavide/Aura", output, approved_seed, FakeExecutor(responses=[json.dumps([run]), json.dumps(view)]))

        # Then
        assert not output.exists()

    def test_given_no_green_run_when_fetched_then_old_output_is_invalidated(self: TestCoverageBaseline, tmp_path: Path) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        output = tmp_path / "report.json"
        output.write_text('{"passed":true}')
        executor = FakeExecutor(responses=["[]"])

        # When
        with pytest.raises(ValueError, match="fully green"):
            fetch_baseline("fardavide/Aura", output, tmp_path / "seed.json", executor)

        # Then
        assert not output.exists()

    def test_given_unsorted_green_runs_when_fetched_then_newest_run_is_selected(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], approved_seed: Path) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        older = {**run, "databaseId": 11, "createdAt": "2026-10-01T10:00:00Z"}
        executor = FakeExecutor(responses=[json.dumps([older, run]), json.dumps(view)])

        # When
        fetch_baseline("fardavide/Aura", tmp_path / "report.json", approved_seed, executor)

        # Then
        assert executor.commands[1][3] == "12"

    def test_given_green_precoverage_run_when_fetched_then_approved_seed_is_copied(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], approved_seed: Path) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        output = tmp_path / "baseline" / "report.json"
        executor = FakeExecutor(responses=[json.dumps([run]), json.dumps(view)])

        # When
        fetch_baseline("fardavide/Aura", output, approved_seed, executor)

        # Then
        assert output.read_bytes() == approved_seed.read_bytes()
        assert executor.commands[1] == ("gh", "run", "view", "12", "--repo", "fardavide/Aura", "--json", "jobs,conclusion,headSha,event")

    @pytest.mark.parametrize(("field_name", "value"), [("approved", False), ("approved", 1), ("kind", "baseline-candidate"), ("passed", None), ("passed", False), ("schema", True), ("schema", 2), ("source_revision", "b" * 40), ("toolchain", ""), ("toolchain", None)])
    def test_given_unapproved_seed_when_fetched_then_output_is_rejected(self: TestCoverageBaseline, tmp_path: Path, run: dict[str, JsonValue], view: dict[str, JsonValue], approved_seed: Path, field_name: str, value: JsonValue) -> None:
        # Given
        from coverage_baseline import fetch_baseline

        fields = decode_json(approved_seed.read_text())
        assert isinstance(fields, dict)
        fields[field_name] = value
        approved_seed.write_text(json.dumps(fields))
        output = tmp_path / "report.json"

        # When
        with pytest.raises(ValueError, match="approved initial baseline"):
            fetch_baseline("fardavide/Aura", output, approved_seed, FakeExecutor(responses=[json.dumps([run]), json.dumps(view)]))

        # Then
        assert not output.exists()
