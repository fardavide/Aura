from __future__ import annotations

from pathlib import Path
import subprocess
import sys

import pytest

import coverage_collect


class TestCaptureJson:
    def test_given_successful_discovery_with_warning_when_json_is_captured_then_warning_is_forwarded_without_unsealed_sidecar(
        self: TestCaptureJson,
        capsys: pytest.CaptureFixture[str],
        tmp_path: Path,
    ) -> None:
        # given
        diagnostic_json = '{"errors": [], "values": []}\n'
        warning = "Discovery used the selected simulator runtime\n"
        command = (
            sys.executable,
            "-c",
            f"import sys; sys.stdout.write({diagnostic_json!r}); sys.stderr.write({warning!r})",
        )
        output = tmp_path / "test-inventory.json"

        # when
        plan = coverage_collect.capture_json(command=command, directory=tmp_path, output=output)

        # then
        assert plan == {"errors": [], "values": []}
        assert output.read_text() == diagnostic_json
        assert not output.with_suffix(output.suffix + ".stderr").exists()
        assert capsys.readouterr().err == warning

    def test_given_discovery_command_fails_when_json_is_captured_then_stdout_and_stderr_are_retained_before_failure_is_raised(
        self: TestCaptureJson,
        tmp_path: Path,
    ) -> None:
        # given
        diagnostic_json = '{"errors": ["Discovery could not load the test bundle"]}\n'
        explanatory_stderr = "The test bundle requires a matching simulator runtime\n"
        command = (
            sys.executable,
            "-c",
            f"import sys; sys.stdout.write({diagnostic_json!r}); "
            f"sys.stderr.write({explanatory_stderr!r}); sys.exit(65)",
        )
        output = tmp_path / "diagnostics" / "test-discovery.json"

        # when
        with pytest.raises(subprocess.CalledProcessError) as failure:
            coverage_collect.capture_json(command=command, directory=tmp_path, output=output)

        # then
        assert failure.value.returncode == 65
        assert output.read_text() == diagnostic_json
        assert output.with_suffix(output.suffix + ".stderr").read_text() == explanatory_stderr
