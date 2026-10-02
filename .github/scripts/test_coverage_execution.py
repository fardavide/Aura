from __future__ import annotations

from pathlib import Path
import re
import shutil
import subprocess


class TestCoverageExecution:
    def test_given_empty_inputs_when_coverage_is_aggregated_then_reports_missing_package_artifact(
        self: TestCoverageExecution,
        tmp_path: Path,
    ) -> None:
        # given
        repository_root = Path(__file__).resolve().parents[2]
        working_root = tmp_path / "repository"
        shutil.copytree(repository_root / ".github/scripts", working_root / ".github/scripts")
        inputs = tmp_path / "inputs"
        inputs.mkdir()
        output = tmp_path / "output"

        # when
        result = subprocess.run(
            [
                "bash",
                ".github/scripts/measure-coverage.sh",
                "--inputs",
                str(inputs),
                "--output",
                str(output),
            ],
            capture_output=True,
            cwd=working_root,
            text=True,
            timeout=10,
        )

        # then
        diagnostic = result.stdout + result.stderr
        assert "missing required package coverage artifact" in diagnostic.casefold(), diagnostic
        assert str(inputs) in diagnostic, diagnostic
        assert result.returncode != 0, diagnostic
        assert re.search(r"\b(pass(?:ed)?|success)\b", diagnostic.casefold()) is None, diagnostic
