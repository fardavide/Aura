from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from functools import partial
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from collect_simulator_diagnostics import SubprocessCommandRunner, collect_diagnostics
from fake_command_runner import FakeCommandRunner


class TestCollectSimulatorDiagnostics(unittest.TestCase):
    def test_given_a_service_query_times_out_when_collecting_then_retains_independent_evidence_and_the_timeout(
        self: TestCollectSimulatorDiagnostics,
    ) -> None:
        # given
        scenario = self.Scenario()
        self.addCleanup(scenario.temporary_directory.cleanup)

        # when
        scenario.sut(output_directory=scenario.output_directory)

        # then
        self.assertIn(
            "812 CoreSimulatorService",
            (scenario.output_directory / "processes.txt").read_text(),
        )
        self.assertIn(
            "CoreSimulator: waiting for SpringBoard registration",
            (scenario.output_directory / "coresimulator-log.txt").read_text(),
        )
        service_diagnostic = (scenario.output_directory / "coresimulator-service.txt").read_text()
        self.assertIn("timed out", service_diagnostic.lower())
        self.assertIn("service query began", service_diagnostic)
        self.assertIn("service reply unavailable", service_diagnostic)
        self.assertTrue(scenario.runner.invocations)
        self.assertTrue(
            all(
                timeout_seconds == 5.0
                for _, timeout_seconds in scenario.runner.invocations
            )
        )

    class Scenario:
        def __init__(self: TestCollectSimulatorDiagnostics.Scenario) -> None:
            self.temporary_directory = tempfile.TemporaryDirectory()
            self.output_directory = Path(self.temporary_directory.name) / "diagnostics"
            self.runner = FakeCommandRunner(
                service_timeout=subprocess.TimeoutExpired(
                    cmd=("launchctl", "print", "CoreSimulatorService"),
                    timeout=5.0,
                    output="service query began\n",
                    stderr="service reply unavailable\n",
                )
            )
            self.sut: partial[None] = partial(
                collect_diagnostics,
                runner=self.runner,
                timeout_seconds=5.0,
            )


class TestSubprocessCommandRunner(unittest.TestCase):
    def test_given_a_diagnostic_process_awaits_enter_when_run_then_confirms_and_retains_output(
        self: TestSubprocessCommandRunner,
    ) -> None:
        # given
        scenario = self.Scenario()

        # when
        result = scenario.sut.run(command=scenario.command, timeout_seconds=5.0)

        # then
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            result.stdout,
            "Press ENTER to continue\nnative diagnostic archive collected\n",
        )
        self.assertEqual(result.stderr, "diagnostic collection finished\n")

    class Scenario:
        def __init__(self: TestSubprocessCommandRunner.Scenario) -> None:
            self.command: tuple[str, ...] = (
                sys.executable,
                "-c",
                "import sys\n"
                "print('Press ENTER to continue', flush=True)\n"
                "if sys.stdin.readline() != '\\n':\n"
                "    print('confirmation missing', file=sys.stderr)\n"
                "    sys.exit(2)\n"
                "print('native diagnostic archive collected')\n"
                "print('diagnostic collection finished', file=sys.stderr)\n",
            )
            self.sut = SubprocessCommandRunner()


if __name__ == "__main__":
    unittest.main()
