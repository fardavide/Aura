from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


class TestPrepareMinimumIosSimulator(unittest.TestCase):
    def test_given_the_minimum_runtime_is_missing_when_preparing_then_downloads_and_exports_a_ready_device(
        self: TestPrepareMinimumIosSimulator,
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
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(
            scenario.github_output.read_text(),
            "simulator_id=MINIMUM-IOS-DEVICE\n",
        )
        invocations = scenario.command_invocations.read_text().splitlines()
        self.assertEqual(len(invocations), 6)
        self.assertEqual(
            invocations[:3],
            [
                "xcrun simctl list runtimes --json",
                "xcodebuild -downloadPlatform iOS -buildVersion 26.0 -architectureVariant arm64",
                "xcrun simctl list runtimes --json",
            ],
        )
        self.assertTrue(invocations[3].startswith("xcrun simctl create "))
        self.assertTrue(
            invocations[3].endswith(
                " com.apple.CoreSimulator.SimDeviceType.iPhone-17 "
                "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
            )
        )
        self.assertEqual(
            invocations[4:],
            [
                "xcrun simctl boot MINIMUM-IOS-DEVICE",
                "xcrun simctl bootstatus MINIMUM-IOS-DEVICE -b",
            ],
        )

    class Scenario:
        def __init__(self: TestPrepareMinimumIosSimulator.Scenario) -> None:
            self.temporary_directory = tempfile.TemporaryDirectory()
            fixture_directory = Path(self.temporary_directory.name)
            self.command_invocations = fixture_directory / "invocations.txt"
            self.command_invocations.write_text("")
            self.github_output = fixture_directory / "github-output.txt"
            self.github_output.write_text("")
            fake_commands_directory = fixture_directory / "fake-commands"
            fake_commands_directory.mkdir()

            xcodebuild = fake_commands_directory / "xcodebuild"
            xcodebuild.write_text(
                '#!/bin/sh\nprintf "xcodebuild %s\\n" "$*" >> "$COMMAND_INVOCATIONS"\n'
                'case "$*" in\n'
                '  "-downloadPlatform iOS -buildVersion 26.0 -architectureVariant arm64")\n'
                '    touch "$DOWNLOADED_RUNTIME" ;;\n'
                '  *) exit 97 ;;\n'
                'esac\n'
            )
            xcodebuild.chmod(0o755)

            xcrun = fake_commands_directory / "xcrun"
            xcrun.write_text(
                '#!/bin/sh\nprintf "xcrun %s\\n" "$*" >> "$COMMAND_INVOCATIONS"\n'
                'case "$*" in\n'
                '  "simctl list runtimes --json")\n'
                '    if [ -f "$DOWNLOADED_RUNTIME" ]; then\n'
                '      printf "%s\\n" "$RUNTIMES_AFTER_DOWNLOAD"\n'
                '    else\n'
                '      printf "%s\\n" "$RUNTIMES_BEFORE_DOWNLOAD"\n'
                '    fi ;;\n'
                '  "simctl create "*)\n'
                '    [ -f "$DOWNLOADED_RUNTIME" ] || exit 96\n'
                '    [ "$4" = "com.apple.CoreSimulator.SimDeviceType.iPhone-17" ] || exit 95\n'
                '    [ "$5" = "com.apple.CoreSimulator.SimRuntime.iOS-26-0" ] || exit 94\n'
                '    printf "%s\\n" "MINIMUM-IOS-DEVICE" ;;\n'
                '  "simctl boot MINIMUM-IOS-DEVICE"|"simctl bootstatus MINIMUM-IOS-DEVICE -b") ;;\n'
                '  *) exit 97 ;;\n'
                'esac\n'
            )
            xcrun.chmod(0o755)
            self.environment: dict[str, str] = {
                "COMMAND_INVOCATIONS": str(self.command_invocations),
                "DOWNLOADED_RUNTIME": str(fixture_directory / "downloaded-runtime"),
                "GITHUB_OUTPUT": str(self.github_output),
                "PATH": f"{fake_commands_directory}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
                "RUNTIMES_AFTER_DOWNLOAD": '{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-0","version":"26.0","buildversion":"23A343","isAvailable":true},{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","buildversion":"24A434","isAvailable":true}]}',
                "RUNTIMES_BEFORE_DOWNLOAD": '{"runtimes":[{"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","buildversion":"24A434","isAvailable":true}]}',
            }
            self.sut: list[str] = [
                "/bin/bash",
                str(Path(__file__).resolve().parents[1] / "prepare-minimum-ios-simulator.sh"),
            ]


if __name__ == "__main__":
    unittest.main()
