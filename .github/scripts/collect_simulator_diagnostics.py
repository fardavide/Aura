from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from typing import Protocol


class CommandRunner(Protocol):
    def run(
        self: CommandRunner,
        command: tuple[str, ...],
        timeout_seconds: float,
    ) -> subprocess.CompletedProcess[str]:
        ...


class SubprocessCommandRunner(CommandRunner):
    def run(
        self: SubprocessCommandRunner,
        command: tuple[str, ...],
        timeout_seconds: float,
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            command,
            capture_output=True,
            check=False,
            input="\n",
            text=True,
            timeout=timeout_seconds,
        )


def collect_diagnostics(
    output_directory: Path,
    runner: CommandRunner,
    timeout_seconds: float,
) -> None:
    output_directory.mkdir(parents=True, exist_ok=True)
    (output_directory / "CoreSimulator").mkdir(exist_ok=True)
    probes: tuple[tuple[str, tuple[str, ...]], ...] = (
        ("processes.txt", ("ps", "-axo", "pid,ppid,state,pcpu,pmem,command")),
        (
            "coresimulator-log.txt",
            (
                "/usr/bin/log", "show", "--last", "25m", "--style", "compact", "--info", "--debug",
                "--predicate",
                'process == "CoreSimulatorService" OR process == "simctl" '
                'OR process == "simdiskimaged" OR process == "launchd_sim" '
                'OR process == "SpringBoard" OR eventMessage CONTAINS "CoreSimulator"',
            ),
        ),
        (
            "coresimulator-service.txt",
            (
                "xcrun", "simctl", "diagnose", "-b", "--timeout=30", "--no-archive",
                f"--output={output_directory / 'CoreSimulator'}",
            ),
        ),
    )
    for filename, command in probes:
        try:
            result = runner.run(command, timeout_seconds)
        except subprocess.TimeoutExpired as error:
            evidence = (
                f"Timed out after {timeout_seconds:g} seconds\n"
                f"{_diagnostic_output(error.stdout)}\n{_diagnostic_output(error.stderr)}"
            )
        else:
            evidence = f"Exit code: {result.returncode}\n{result.stdout}\n{result.stderr}"
        (output_directory / filename).write_text(
            f"Command: {' '.join(command)}\n{evidence}", encoding="utf-8"
        )


def _diagnostic_output(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if isinstance(value, str):
        return value
    raise TypeError("Unexpected subprocess diagnostic output type")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: collect_simulator_diagnostics.py OUTPUT_DIRECTORY")
    collect_diagnostics(Path(sys.argv[1]), SubprocessCommandRunner(), 60.0)
