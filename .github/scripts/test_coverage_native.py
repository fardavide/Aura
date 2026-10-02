"""Opt-in native collection acceptance; excluded from the fast tooling suite."""

from dataclasses import asdict
import json
from pathlib import Path
import subprocess
import sys

import pytest


@pytest.mark.native
class TestNativeCollection:
    def test_given_app_hosted_run_when_collecting_then_all_enumerated_methods_complete_once(
        self: "TestNativeCollection",
        tmp_path: Path,
    ) -> None:
        import coverage_collect
        from coverage_artifacts import validate_artifact
        from coverage_inventory import decode_json, enumerated_ios_tests, verify_ios_tests

        # given
        root = Path(__file__).resolve().parents[2]
        coverage_collect.prepare_local(root=root)
        identity = coverage_collect.create_context(root)
        context = tmp_path / "context.json"
        context.write_text(json.dumps(asdict(identity)))
        inputs = tmp_path / "inputs"
        destination = inputs / "ios"
        derived = tmp_path / "derived/ios"
        coverage_collect.build_ios(derived=derived, identity=identity, root=root)

        # when
        subprocess.run(
            (
                sys.executable, str(Path(coverage_collect.__file__).resolve()), "ios",
                "--context", str(context), "--derived", str(derived), "--inputs", str(inputs),
            ),
            check=True,
            cwd=root,
        )

        # then
        artifact = validate_artifact(destination / "manifest.json", identity, "ios")
        expected = enumerated_ios_tests(decode_json((destination / "enumerated-tests.json").read_text()))
        completed = verify_ios_tests(
            expected=expected,
            inventory=decode_json((destination / "test-inventory.json").read_text()),
            summary=decode_json((destination / "test-summary.json").read_text()),
        )
        assert completed == expected
        assert decode_json((destination / "planned-tests.json").read_text()) == list(expected)
        assert decode_json((destination / "completed-tests.json").read_text()) == list(completed)
        assert artifact.objects

    def test_given_required_package_run_when_collecting_then_all_enumerated_native_cases_have_valid_artifact(
        self: "TestNativeCollection",
        tmp_path: Path,
    ) -> None:
        import coverage_collect
        from coverage_artifacts import validate_artifact
        from coverage_inventory import decode_json, package_methods, verify_package_events

        # given
        root = Path(__file__).resolve().parents[2]
        identity = coverage_collect.create_context(root)
        destination = tmp_path / "inputs/package"

        # when
        coverage_collect.collect_package(destination=destination, identity=identity, root=root)

        # then
        artifact = validate_artifact(destination / "manifest.json", identity, "package")
        enumeration = decode_json((destination / "enumerated-tests.json").read_text())
        assert isinstance(enumeration, list)
        methods = tuple(method for method in enumeration if isinstance(method, str))
        assert len(methods) == len(enumeration)
        expected = package_methods("\n".join(methods))
        planned, completed = verify_package_events(
            expected=expected,
            records=tuple(
                decode_json(line)
                for line in (destination / "native-events.jsonl").read_text().splitlines()
                if line.strip()
            ),
        )
        assert decode_json((destination / "planned-tests.json").read_text()) == list(planned)
        assert decode_json((destination / "completed-tests.json").read_text()) == list(completed)
        assert artifact.objects
