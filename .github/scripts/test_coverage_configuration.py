from pathlib import Path
import shlex
import subprocess
import xml.etree.ElementTree as Xml


class TestCoverageConfiguration:
    def test_given_parallel_make_when_coverage_runs_then_compiles_unsigned_macos_sequentially_before_report(
        self: TestCoverageConfiguration,
    ) -> None:
        # given
        root = Path(__file__).resolve().parents[2]

        # when
        result = subprocess.run(
            ("make", "--dry-run", "coverage", "--jobs=2"),
            capture_output=True,
            check=True,
            cwd=root,
            text=True,
            timeout=10,
        )

        # then
        commands = [tuple(shlex.split(line)) for line in result.stdout.splitlines() if line.strip()]
        macos_builds = [
            command for command in commands
            if command[:2] == ("xcodebuild", "build") and "generic/platform=macOS" in command
        ]
        assert len(macos_builds) == 1, "make coverage must include the required macOS app compile gate"
        macos_build = macos_builds[0]
        assert macos_build[macos_build.index("-scheme") + 1] == "Aura"
        assert {
            "CODE_SIGN_IDENTITY=", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO",
        }.issubset(macos_build)
        assert 0 < int(macos_build[macos_build.index("-jobs") + 1]) <= 4
        ios_collections = [
            command for command in commands
            if ".github/scripts/coverage_collect.py" in command and "ios" in command
        ]
        assert len(ios_collections) == 2
        report = next(command for command in commands if ".github/scripts/coverage_aggregate.py" in command)
        assert "--baseline" in report
        assert max(commands.index(command) for command in ios_collections) < commands.index(macos_build)
        assert commands.index(macos_build) < commands.index(report)

    def test_when_building_ios_test_products_then_in_process_parallelization_is_disabled(self) -> None:
        # given
        scheme = Path(__file__).resolve().parents[2] / "Aura.xcodeproj/xcshareddata/xcschemes/Aura.xcscheme"

        # when
        testables = Xml.parse(scheme).findall(".//TestableReference")

        # then
        assert testables
        assert all(testable.get("parallelizable") == "NO" for testable in testables)
