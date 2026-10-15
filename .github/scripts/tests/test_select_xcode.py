from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path


class TestSelectXcode(unittest.TestCase):
    def test_given_a_different_build_when_selecting_then_fails_with_the_expected_and_actual_build(
        self: TestSelectXcode,
    ) -> None:
        # given
        scenario = self.Scenario(xcode_version="Xcode 27.0\nBuild version WRONG-BUILD")
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
        self.assertIn("27A266a", result.stdout + result.stderr)
        self.assertIn("WRONG-BUILD", result.stdout + result.stderr)

    def test_given_only_other_xcode_versions_when_selecting_then_fails_without_fallback(
        self: TestSelectXcode,
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
        self.assertIn(
            str(scenario.applications_directory / "Xcode_27.0.app"),
            result.stdout + result.stderr,
        )
        self.assertEqual(scenario.command_invocations.read_text(), "")

    class Scenario:
        def __init__(
            self: TestSelectXcode.Scenario,
            xcode_version: str | None = None,
        ) -> None:
            self.temporary_directory = tempfile.TemporaryDirectory()
            fixture_directory = Path(self.temporary_directory.name)
            self.applications_directory = fixture_directory / "Applications"
            self.applications_directory.mkdir()
            for app_name in ("Xcode_26.0.app", "Xcode_27.1.app"):
                (
                    self.applications_directory
                    / app_name
                    / "Contents"
                    / "Developer"
                ).mkdir(parents=True)
            if xcode_version is not None:
                (self.applications_directory / "Xcode_27.0.app").mkdir()

            self.command_invocations = fixture_directory / "command-invocations.txt"
            self.command_invocations.write_text("")
            fake_commands_directory = fixture_directory / "fake-commands"
            fake_commands_directory.mkdir()
            for command_name in ("sudo", "xcode-select"):
                executable = fake_commands_directory / command_name
                executable.write_text(
                    "#!/bin/sh\n"
                    'printf "%s\\n" "$0 $*" >> "$COMMAND_INVOCATIONS"\n'
                    "exit 0\n"
                )
                executable.chmod(0o755)

            xcodebuild = fake_commands_directory / "xcodebuild"
            xcodebuild.write_text('#!/bin/sh\nprintf "%s\\n" "$XCODE_VERSION"\n')
            xcodebuild.chmod(0o755)

            self.environment: dict[str, str] = {
                "COMMAND_INVOCATIONS": str(self.command_invocations),
                "PATH": f"{fake_commands_directory}:/usr/bin:/bin",
                "XCODE_VERSION": xcode_version or "",
            }
            self.sut: list[str] = [
                "/bin/bash",
                str(Path(__file__).resolve().parents[1] / "select-xcode.sh"),
                str(self.applications_directory),
            ]


if __name__ == "__main__":
    unittest.main()
