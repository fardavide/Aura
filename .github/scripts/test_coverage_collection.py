"""Collection keeps native tests in their owning containers."""

from pathlib import Path
from dataclasses import asdict
import json
import shutil
import subprocess
import sys

import pytest


class TestPackageCollection:
    def test_given_previous_local_collection_when_preparing_again_then_archives_only_owned_outputs_and_preserves_work(
        self: "TestPackageCollection",
        tmp_path: Path,
    ) -> None:
        import coverage_collect
        from coverage_artifacts import CollectionIdentity

        # Given
        identity = CollectionIdentity(
            architecture="arm64", configuration="Debug-instrumented-v1", revision="a" * 40,
            run="local:previous-run", source_digest="b" * 64, source_root=str(tmp_path), toolchain="previous-toolchain",
        )
        owned = {
            "coverage-context.json": json.dumps(asdict(identity)).encode(),
            "coverage-inputs/package/manifest.json": b"completed package artifact",
            "coverage-inputs/ios-0/profile.profdata": b"completed native counters",
            "coverage/report.json": b"previous report",
            "coverage-diagnostics/ios-build.log": b"prior native diagnostics",
            "coverage-diagnostics/ios-0.xcresult/Data/receipt": b"prior native results",
            "ios-products.json": b"previous product provenance",
            "ios-products.tar.gz": b"previous product archive",
        }
        unrelated = {
            "build/derived/ios/Build/Products/Aura": b"reusable compiled binary",
            "build/derived/ios/Build/Products/coverage-build.json": b"reusable build stamp",
            "AuraKit/.build/package-tests": b"reusable package products",
            "build/coverage-reference/notes.txt": b"reference evidence",
            "build/coverage-validation/package/manifest.json": b"acceptance evidence",
            "build/work-in-progress/notes.txt": b"unrelated work",
        }
        for filename, contents in {**{f"build/{name}": value for name, value in owned.items()}, **unrelated}.items():
            path = tmp_path / filename
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)

        # When
        archived = coverage_collect.prepare_local(root=tmp_path)

        # Then
        assert isinstance(archived, Path)
        assert archived.parent == tmp_path / "build/coverage-history"
        for filename, contents in owned.items():
            assert (archived / filename).read_bytes() == contents
            assert not (tmp_path / "build" / filename).exists()
        for filename, contents in unrelated.items():
            assert (tmp_path / filename).read_bytes() == contents

    @pytest.mark.parametrize("context_root", ["current", "compiled"])
    def test_given_products_compiled_in_another_checkout_when_restored_then_rejects_before_extraction(
        self: "TestPackageCollection",
        tmp_path: Path,
        context_root: str,
    ) -> None:
        from coverage_artifacts import CollectionIdentity
        from coverage_products import archive_products, source_digest

        # Given
        root = tmp_path / "checkout"
        scripts = root / ".github/scripts"
        shutil.copytree(Path(__file__).parent, scripts)
        for filename in ("Aura/App.swift", "AuraKit/Sources/Feature.swift"):
            source = root / filename
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("struct Source {}")
        compiled_root = tmp_path / "original-checkout"
        identity = CollectionIdentity(
            architecture="arm64", configuration="Debug-instrumented-v1", revision="a" * 40,
            run="github:12:1", source_digest=source_digest(root),
            source_root=str(root if context_root == "current" else compiled_root), toolchain="matching-test-toolchain",
        )
        build = root / "build"
        products = build / "prepared-products"
        products.mkdir(parents=True)
        (products / "Aura").write_bytes(b"compiled mapping")
        archive = archive_products(products, build / "ios-products.tar.gz")
        (build / "coverage-context.json").write_text(json.dumps(asdict(identity)))
        (build / "ios-products.json").write_text(json.dumps({
            "sha256": archive.sha256, "identity": {**asdict(identity), "source_root": str(compiled_root)},
        }))

        # When
        result = subprocess.run(
            (sys.executable, str(scripts / "coverage_collect.py"), "restore-products"),
            cwd=root, capture_output=True, text=True,
        )

        # Then
        assert result.returncode != 0, result.stdout
        assert "compiled source root" in result.stderr.lower()
        assert "incompatible" in result.stderr.lower()
        assert not (build / "derived/ios/Build/Products").exists()

    @pytest.mark.native
    def test_given_compiled_native_binary_when_collection_is_sealed_then_mapping_preserves_build_timestamp(
        self: "TestPackageCollection",
        tmp_path: Path,
    ) -> None:
        import coverage_collect

        # Given
        root = Path(__file__).resolve().parents[2]
        source = root / "AuraKit/.build/out/Products/Debug/CommonDesignTests.xctest/Contents/MacOS/CommonDesignTests"
        source_timestamp = source.stat().st_mtime_ns
        identity = coverage_collect.read_context(root / "build/coverage-context.json")
        destination = tmp_path / "package"
        destination.mkdir()
        receipts = root / "build/coverage-inputs/package"
        for filename in ("profile.profdata", "planned-tests.json", "completed-tests.json", "enumerated-tests.json"):
            shutil.copy2(receipts / filename, destination / filename)
        assert source_timestamp < (destination / "profile.profdata").stat().st_mtime_ns

        # When
        coverage_collect.seal_collection(
            destination=destination, identity=identity, objects=(source,), platform_name="macOS", root=root, suite="package",
        )

        # Then
        mapping = destination / "objects/000/CommonDesignTests"
        assert mapping.stat().st_mtime_ns == source_timestamp

    def test_given_package_when_collecting_then_run_in_package_container(self: "TestPackageCollection", tmp_path: Path) -> None:
        import coverage_collect

        command, directory = coverage_collect.package_test_command(root=tmp_path, events=tmp_path / "events.jsonl")

        assert directory == tmp_path / "AuraKit"
        assert command[:2] == ("swift", "test")
        assert "--enable-code-coverage" in command
        assert command[command.index("--experimental-event-stream-version") + 1] == "0"
        assert "--skip-build" not in command

    def test_given_warm_products_when_preparing_then_clear_only_counters(self: "TestPackageCollection", tmp_path: Path) -> None:
        import coverage_collect

        product = tmp_path / "Products" / "AuraTests"
        product.parent.mkdir()
        product.write_bytes(b"compiled product")
        counter = tmp_path / "ProfileData" / "Coverage.profdata"
        counter.parent.mkdir()
        counter.write_bytes(b"old counters")
        raw = product.parent / "default.profraw"
        raw.write_bytes(b"old raw counters")

        coverage_collect.clear_counters(tmp_path)

        assert product.read_bytes() == b"compiled product"
        assert not counter.exists()
        assert not raw.exists()

    def test_given_native_failure_when_running_then_keep_exit_and_diagnostics(self: "TestPackageCollection", tmp_path: Path) -> None:
        import coverage_collect
        import subprocess
        import sys
        import pytest

        log = tmp_path / "tests.log"
        with pytest.raises(subprocess.CalledProcessError) as failure:
            coverage_collect.run_logged(command=(sys.executable, "-c", "print('native failure'); raise SystemExit(65)"), directory=tmp_path, log=log)

        assert failure.value.returncode == 65
        assert "native failure" in log.read_text()

    def test_given_new_local_collection_when_identifying_then_never_mix_attempts(self: "TestPackageCollection") -> None:
        import coverage_collect

        assert coverage_collect.run_identity({}) != coverage_collect.run_identity({})
        assert coverage_collect.run_identity({"GITHUB_RUN_ID": "321", "GITHUB_RUN_ATTEMPT": "2"}) == "github:321:2"

    def test_given_ios_shard_when_executing_then_reuse_products_and_serialize_whole_suites(self: "TestPackageCollection", tmp_path: Path) -> None:
        import coverage_collect

        command = coverage_collect.ios_test_command(derived=tmp_path, destination="platform=iOS Simulator,id=ABC", plan=tmp_path / "Aura.xctestrun", result=tmp_path / "results.xcresult", suites=("CameraGridSnapshotTests", "SettingsSnapshotTests"))

        assert command[:2] == ("xcodebuild", "test-without-building")
        assert command[command.index("-parallel-testing-enabled") + 1] == "NO"
        assert command[command.index("-enableCodeCoverage") + 1] == "YES"
        assert "-only-testing:AuraTests/CameraGridSnapshotTests" in command
        assert "-only-testing:AuraTests/SettingsSnapshotTests" in command

    def test_given_successful_native_export_when_capturing_then_preserve_json_receipt(self: "TestPackageCollection", tmp_path: Path) -> None:
        import coverage_collect
        import sys

        path = tmp_path / "receipt.json"
        value = coverage_collect.capture_json(command=(sys.executable, "-c", "print('{\"result\":\"Passed\"}')"), directory=tmp_path, output=path)

        assert value == {"result": "Passed"}
        assert '"Passed"' in path.read_text()

    def test_given_local_command_when_requested_then_exposes_collectors_and_receipt_validation(self: "TestPackageCollection") -> None:
        import subprocess
        import sys

        result = subprocess.run((sys.executable, str(Path(__file__).with_name("coverage_collect.py")), "--help"), capture_output=True, text=True)

        assert result.returncode == 0
        for command in ("context", "package", "ios-build", "ios", "verify-ios", "products", "restore-products"):
            assert command in result.stdout

    def test_given_available_runtimes_when_isolating_snapshots_then_preserve_ios_26(self: "TestPackageCollection") -> None:
        import coverage_collect

        runtime = coverage_collect.snapshot_runtime({"runtimes": [
            {"identifier": "ios-27", "isAvailable": True, "name": "iOS 27.0", "version": "27.0"},
            {"identifier": "ios-26-5", "isAvailable": True, "name": "iOS 26.5", "version": "26.5"},
            {"identifier": "ios-26-6", "isAvailable": False, "name": "iOS 26.6", "version": "26.6"},
        ]})

        assert runtime == "ios-26-5"

    def test_given_root_relative_receipt_when_package_changes_directory_then_keep_receipt_at_root(self: "TestPackageCollection", tmp_path: Path) -> None:
        import coverage_collect

        command, _ = coverage_collect.package_test_command(events=Path("build/events.jsonl"), root=tmp_path)

        assert command[command.index("--event-stream-output-path") + 1] == str(tmp_path / "build/events.jsonl")
