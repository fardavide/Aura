from __future__ import annotations

import subprocess
from pathlib import Path

from collect_simulator_diagnostics import CommandRunner


class FakeCommandRunner(CommandRunner):
    def __init__(
        self: FakeCommandRunner,
        service_timeout: subprocess.TimeoutExpired,
    ) -> None:
        self.invocations: list[tuple[tuple[str, ...], float]] = []
        self.service_timeout = service_timeout

    def run(
        self: FakeCommandRunner,
        command: tuple[str, ...],
        timeout_seconds: float,
    ) -> subprocess.CompletedProcess[str]:
        self.invocations.append((command, timeout_seconds))
        match Path(command[0]).name:
            case "ps":
                return subprocess.CompletedProcess(
                    args=command,
                    returncode=0,
                    stderr="",
                    stdout="812 CoreSimulatorService\n913 Simulator\n",
                )
            case "log":
                return subprocess.CompletedProcess(
                    args=command,
                    returncode=0,
                    stderr="",
                    stdout="CoreSimulator: waiting for SpringBoard registration\n",
                )
            case "launchctl" | "xcrun":
                raise self.service_timeout
            case _:
                raise NotImplementedError(f"Unexpected diagnostic command: {command!r}")
