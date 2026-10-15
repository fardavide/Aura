from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


class TestPrepareSnapshotSimulator(unittest.TestCase):
    def test_given_the_expected_runtime_when_preparing_then_exports_a_ready_test_owned_device(
        self: TestPrepareSnapshotSimulator,
    ) -> None:
        # given
        scenario = self.Scenario(
            runtime_json='{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","buildversion":"24A434","isAvailable":true}]}'
        )
        self.addCleanup(scenario.temporary_directory.cleanup)

        # when
        result = subprocess.run(
            scenario.sut,
            capture_output=True,
            env=scenario.environment,
            text=True,
            timeout=10,
        )

        # then
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            scenario.github_output.read_text(),
            "simulator_id=TEST-OWNED-DEVICE\n",
        )
        self.assertEqual(
            scenario.command_invocations.read_text().splitlines(),
            [
                "simctl list runtimes --json",
                "simctl create Aura-Snapshots com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "simctl boot TEST-OWNED-DEVICE",
                "simctl bootstatus TEST-OWNED-DEVICE -b",
            ],
        )

    def test_given_only_a_newer_runtime_when_preparing_then_fails_without_creating_a_device(
        self: TestPrepareSnapshotSimulator,
    ) -> None:
        # given
        scenario = self.Scenario()
        self.addCleanup(scenario.temporary_directory.cleanup)

        # when
        result = subprocess.run(
            scenario.sut,
            capture_output=True,
            env=scenario.environment,
            text=True,
            timeout=10,
        )

        # then
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("iOS 27.0 build 24A434", result.stdout + result.stderr)
        self.assertEqual(
            scenario.command_invocations.read_text().splitlines(),
            ["simctl list runtimes --json"],
        )

    class Scenario:
        def __init__(
            self: TestPrepareSnapshotSimulator.Scenario,
            runtime_json: str = '{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-1","version":"27.1","buildversion":"24B999","isAvailable":true}]}',
        ) -> None:
            self.temporary_directory = tempfile.TemporaryDirectory()
            fixture_directory = Path(self.temporary_directory.name)
            self.command_invocations = fixture_directory / "invocations.txt"
            self.command_invocations.write_text("")
            self.github_output = fixture_directory / "github-output.txt"
            self.github_output.write_text("")
            fake_commands_directory = fixture_directory / "fake-commands"
            fake_commands_directory.mkdir()
            xcrun = fake_commands_directory / "xcrun"
            xcrun.write_text(
                '#!/bin/sh\nprintf "%s\\n" "$*" >> "$COMMAND_INVOCATIONS"\n'
                'case "$*" in\n'
                '  "simctl list runtimes --json") printf "%s\\n" "$RUNTIMES" ;;\n'
                '  "simctl create "*) printf "%s\\n" "TEST-OWNED-DEVICE" ;;\n'
                '  "simctl boot TEST-OWNED-DEVICE"|"simctl bootstatus TEST-OWNED-DEVICE -b") ;;\n'
                '  *) exit 97 ;;\n'
                'esac\n'
            )
            xcrun.chmod(0o755)
            self.environment: dict[str, str] = {
                "COMMAND_INVOCATIONS": str(self.command_invocations),
                "GITHUB_OUTPUT": str(self.github_output),
                "PATH": f"{fake_commands_directory}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
                "RUNTIMES": runtime_json,
            }
            self.sut: list[str] = [
                "/bin/bash",
                str(Path(__file__).resolve().parents[1] / "prepare-snapshot-simulator.sh"),
            ]


if __name__ == "__main__":
    unittest.main()
