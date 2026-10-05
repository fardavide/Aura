"""Collection keeps native tests in their owning containers."""

from __future__ import annotations

from collections.abc import Iterator, Sequence
from contextlib import AbstractContextManager, contextmanager
from pathlib import Path
from dataclasses import asdict
from hashlib import sha256
import json
import plistlib
import shutil
import subprocess
import sys
from typing import Literal, TextIO

import pytest


class TestIosCollection:
    def test_given_native_boot_failure_and_receipt_close_failure_when_context_starts_then_preserves_native_error_and_cleans_device(
        self: TestIosCollection,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect

        boot_command = ("xcrun", "simctl", "bootstatus", "failed-snapshot-simulator", "-b")
        boot_failure = subprocess.CalledProcessError(
            returncode=70, cmd=boot_command,
            output="original native boot progress\n", stderr="original native boot failure\n",
        )
        native_commands: list[tuple[str, ...]] = []
        diagnostic = tmp_path / "build/coverage-diagnostics/simulator-failed-snapshot-simulator.log"
        original_open = Path.open

        @contextmanager
        def failing_close(receipt: TextIO) -> Iterator[TextIO]:
            with receipt:
                try:
                    yield receipt
                finally:
                    raise OSError("Boot diagnostic flush failed")

        def open_file(
            path: Path,
            mode: Literal["r", "w", "a"] = "r",
            buffering: int = -1,
            encoding: str | None = None,
            errors: str | None = None,
            newline: str | None = None,
        ) -> AbstractContextManager[TextIO]:
            receipt = original_open(path, mode, buffering, encoding, errors, newline)
            if path == diagnostic and mode == "w":
                return failing_close(receipt)
            return receipt

        def run(
            command: Sequence[str],
            *,
            capture_output: bool = False,
            check: bool = False,
            cwd: Path | None = None,
            text: bool = False,
            timeout: float | None = None,
        ) -> subprocess.CompletedProcess[str]:
            assert tuple(command[:2]) == ("xcrun", "simctl")
            native_commands.append(tuple(command))
            match command[2]:
                case "list":
                    stdout = json.dumps({"runtimes": [{
                        "identifier": "ios-26-6", "isAvailable": True, "name": "iOS 26.6", "version": "26.6",
                    }]})
                case "create":
                    stdout = "failed-snapshot-simulator\n"
                case "bootstatus":
                    assert tuple(command) == boot_command
                    assert check is True
                    raise boot_failure
                case "shutdown" | "delete":
                    assert command[-1] == "failed-snapshot-simulator"
                    stdout = ""
                case _:
                    raise AssertionError(f"Unexpected simulator lifecycle command: {command}")
            return subprocess.CompletedProcess(command, returncode=0, stdout=stdout, stderr="")

        monkeypatch.setattr(coverage_collect.subprocess, "run", run)
        monkeypatch.setattr(Path, "open", open_file)

        # when
        with pytest.raises((subprocess.CalledProcessError, OSError)) as failure:
            with coverage_collect.snapshot_simulator(root=tmp_path):
                pytest.fail("A failed native boot must not yield an owned device")

        # then
        assert failure.value is boot_failure, "Closing the boot diagnostic must preserve the original native failure"
        assert boot_failure.returncode == 70
        assert boot_failure.stdout == "original native boot progress\n"
        assert boot_failure.stderr == "original native boot failure\n"
        assert [command[2] for command in native_commands] == ["list", "create", "bootstatus", "shutdown", "delete"]

    def test_given_blocked_lifecycle_diagnostic_directory_when_owned_device_is_created_then_cleans_device_and_preserves_directory_error(
        self: TestIosCollection,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect

        blocked_directory = tmp_path / "build/coverage-diagnostics"
        blocked_directory.parent.mkdir()
        blocked_directory.write_bytes(b"existing regular file must remain unchanged")
        native_commands: list[tuple[str, ...]] = []

        def run(
            command: Sequence[str],
            *,
            capture_output: bool = False,
            check: bool = False,
            cwd: Path | None = None,
            text: bool = False,
            timeout: float | None = None,
        ) -> subprocess.CompletedProcess[str]:
            assert tuple(command[:2]) == ("xcrun", "simctl")
            native_commands.append(tuple(command))
            match command[2]:
                case "list":
                    stdout = json.dumps({"runtimes": [{
                        "identifier": "ios-26-6", "isAvailable": True, "name": "iOS 26.6", "version": "26.6",
                    }]})
                case "create":
                    stdout = "owned-snapshot-simulator\n"
                case "shutdown" | "delete":
                    assert command[-1] == "owned-snapshot-simulator"
                    stdout = ""
                case _:
                    raise AssertionError(f"No native boot may run after diagnostics directory failure: {command}")
            return subprocess.CompletedProcess(command, returncode=0, stdout=stdout, stderr="")

        monkeypatch.setattr(coverage_collect.subprocess, "run", run)

        # when
        with pytest.raises(OSError) as failure:
            with coverage_collect.snapshot_simulator(root=tmp_path):
                pytest.fail("A blocked diagnostics directory must prevent yielding an owned device")

        # then
        assert isinstance(failure.value, FileExistsError), "Cleanup logging must preserve the original diagnostics-directory creation error"
        assert failure.value.filename == str(blocked_directory)
        assert [command[2] for command in native_commands] == ["list", "create", "shutdown", "delete"]
        assert blocked_directory.read_bytes() == b"existing regular file must remain unchanged"

    def test_given_owned_boot_and_delete_failures_when_context_starts_then_preserves_boot_error_and_records_cleanup_failure(
        self: TestIosCollection,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect

        boot_command = ("xcrun", "simctl", "bootstatus", "failed-snapshot-simulator", "-b")
        boot_failure = subprocess.CalledProcessError(
            returncode=70, cmd=boot_command,
            output="primary boot progress\n", stderr="primary boot failure\n",
        )
        native_commands: list[tuple[str, ...]] = []

        def run(
            command: Sequence[str],
            *,
            capture_output: bool = False,
            check: bool = False,
            cwd: Path | None = None,
            text: bool = False,
            timeout: float | None = None,
        ) -> subprocess.CompletedProcess[str]:
            assert tuple(command[:2]) == ("xcrun", "simctl")
            native_commands.append(tuple(command))
            match command[2]:
                case "list":
                    stdout = json.dumps({"runtimes": [{
                        "identifier": "ios-26-6", "isAvailable": True, "name": "iOS 26.6", "version": "26.6",
                    }]})
                case "create":
                    stdout = "failed-snapshot-simulator\n"
                case "bootstatus":
                    assert tuple(command) == boot_command
                    assert check is True
                    raise boot_failure
                case "shutdown":
                    assert command[-1] == "failed-snapshot-simulator"
                    stdout = ""
                case "delete":
                    assert check is True
                    assert command[-1] == "failed-snapshot-simulator"
                    raise subprocess.CalledProcessError(
                        returncode=72, cmd=command,
                        output="secondary delete progress\n", stderr="secondary delete cleanup failure\n",
                    )
                case _:
                    raise AssertionError(f"Unexpected simulator lifecycle command: {command}")
            return subprocess.CompletedProcess(command, returncode=0, stdout=stdout, stderr="")

        monkeypatch.setattr(coverage_collect.subprocess, "run", run)

        # when
        with pytest.raises(subprocess.CalledProcessError) as failure:
            with coverage_collect.snapshot_simulator(root=tmp_path):
                pytest.fail("A failed owned simulator boot must not yield a device")

        # then
        assert failure.value is boot_failure, "Owned cleanup must preserve the original native boot exception"
        assert failure.value.returncode == 70
        assert [command[2] for command in native_commands] == ["list", "create", "bootstatus", "shutdown", "delete"]
        diagnostic = (tmp_path / "build/coverage-diagnostics/simulator-failed-snapshot-simulator.log").read_text()
        for evidence in (
            "primary boot progress", "primary boot failure",
            "secondary delete progress", "secondary delete cleanup failure",
        ):
            assert evidence in diagnostic

    def test_given_owned_simulator_boot_failure_when_context_starts_then_retains_native_diagnostics_and_cleans_without_yielding(
        self: TestIosCollection,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect

        boot_command = ("xcrun", "simctl", "bootstatus", "failed-snapshot-simulator", "-b")
        boot_failure = subprocess.CalledProcessError(
            returncode=70, cmd=boot_command,
            output="native boot progress before failure\n", stderr="native boot service could not initialize\n",
        )
        native_commands: list[tuple[str, ...]] = []

        def run(
            command: Sequence[str],
            *,
            capture_output: bool = False,
            check: bool = False,
            cwd: Path | None = None,
            text: bool = False,
            timeout: float | None = None,
        ) -> subprocess.CompletedProcess[str]:
            assert tuple(command[:2]) == ("xcrun", "simctl")
            native_commands.append(tuple(command))
            match command[2]:
                case "list":
                    stdout = json.dumps({"runtimes": [{
                        "identifier": "ios-26-6", "isAvailable": True, "name": "iOS 26.6", "version": "26.6",
                    }]})
                case "create":
                    stdout = "failed-snapshot-simulator\n"
                case "bootstatus":
                    assert tuple(command) == boot_command
                    assert check is True
                    assert timeout is not None and 0 < timeout <= 180
                    raise boot_failure
                case "shutdown" | "delete":
                    assert command[-1] == "failed-snapshot-simulator"
                    stdout = ""
                case _:
                    raise AssertionError(f"Unexpected simulator lifecycle command: {command}")
            return subprocess.CompletedProcess(command, returncode=0, stdout=stdout, stderr="")

        monkeypatch.setattr(coverage_collect.subprocess, "run", run)

        # when
        with pytest.raises(subprocess.CalledProcessError) as failure:
            with coverage_collect.snapshot_simulator(root=tmp_path):
                pytest.fail("A failed owned simulator boot must not yield a device")

        # then
        assert failure.value is boot_failure
        assert [command[2] for command in native_commands] == ["list", "create", "bootstatus", "shutdown", "delete"]
        diagnostic = (tmp_path / "build/coverage-diagnostics/simulator-failed-snapshot-simulator.log").read_text()
        assert "native boot progress before failure" in diagnostic
        assert "native boot service could not initialize" in diagnostic

    def test_given_borrowed_simulator_when_context_yields_then_preserves_caller_device_without_owned_lifecycle_commands(
        self: TestIosCollection,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        # given
        import coverage_collect

        def run(
            command: Sequence[str],
            *,
            capture_output: bool = False,
            check: bool = False,
            cwd: Path | None = None,
            text: bool = False,
            timeout: float | None = None,
        ) -> subprocess.CompletedProcess[str]:
            raise AssertionError(f"Borrowed simulators must retain caller ownership: {command}")

        monkeypatch.setattr(coverage_collect.subprocess, "run", run)

        # when
        with coverage_collect.snapshot_simulator(provided="caller-simulator") as simulator:
            # then
            assert simulator == "caller-simulator"

    def test_given_owned_disposable_simulator_when_context_yields_then_is_fully_booted_before_use_and_cleaned_afterward(
        self: TestIosCollection,
        monkeypatch: pytest.MonkeyPatch,
    ) -> None:
        # given
        import coverage_collect

        events: list[str] = []
        booted = False

        def run(
            command: Sequence[str],
            *,
            capture_output: bool = False,
            check: bool = False,
            cwd: Path | None = None,
            text: bool = False,
            timeout: float | None = None,
        ) -> subprocess.CompletedProcess[str]:
            nonlocal booted
            assert tuple(command[:2]) == ("xcrun", "simctl")
            events.append(command[2])
            match command[2]:
                case "list":
                    assert tuple(command[2:]) == ("list", "runtimes", "--json")
                    stdout = json.dumps({"runtimes": [{
                        "identifier": "ios-26-6", "isAvailable": True, "name": "iOS 26.6", "version": "26.6",
                    }]})
                case "create":
                    assert command[-1] == "ios-26-6"
                    stdout = "owned-snapshot-simulator\n"
                case "bootstatus":
                    assert tuple(command[3:]) == ("owned-snapshot-simulator", "-b")
                    assert check is True
                    assert timeout is not None and 0 < timeout <= 180
                    booted = True
                    stdout = "Fully booted\n"
                case "shutdown":
                    assert command[-1] == "owned-snapshot-simulator"
                    booted = False
                    stdout = ""
                case "delete":
                    assert command[-1] == "owned-snapshot-simulator"
                    stdout = ""
                case _:
                    raise AssertionError(f"Unexpected simulator lifecycle command: {command}")
            return subprocess.CompletedProcess(command, returncode=0, stdout=stdout, stderr="")

        monkeypatch.setattr(coverage_collect.subprocess, "run", run)

        # when
        with coverage_collect.snapshot_simulator() as simulator:
            assert simulator == "owned-snapshot-simulator"
            assert booted, "Disposable snapshot simulators must complete bootstatus before the context yields"
            events.append("use")

        # then
        assert events == ["list", "create", "bootstatus", "use", "shutdown", "delete"]
        assert booted is False

    def test_given_incomplete_native_settings_when_host_initialization_times_out_then_retains_reason_and_restores_simulator(
        self: TestIosCollection,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect

        products = tmp_path / "Products"
        app = products / "Debug-iphonesimulator/Aura.app"
        app.mkdir(parents=True)
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "fardavide.Aura"}))
        container = tmp_path / "Simulator/AppData"
        preferences = container / "Library/Preferences/fardavide.Aura.plist"
        native_commands: list[tuple[str, ...]] = []
        elapsed_seconds = [0.0]

        def run(
            command: Sequence[str],
            *,
            capture_output: bool = False,
            check: bool = False,
            cwd: Path | None = None,
            text: bool = False,
            timeout: float | None = None,
        ) -> subprocess.CompletedProcess[str]:
            assert tuple(command[:2]) == ("xcrun", "simctl")
            assert check is True
            native_commands.append(tuple(command))
            match command[2]:
                case "list":
                    stdout = json.dumps({"devices": {"ios-26-5": [
                        {"udid": "prepared-simulator", "state": "Shutdown"},
                    ]}})
                case "bootstatus" | "install" | "terminate" | "shutdown":
                    stdout = ""
                case "launch":
                    assert not preferences.exists()
                    preferences.parent.mkdir(parents=True)
                    preferences.write_bytes(plistlib.dumps({"theme": "system"}))
                    stdout = "fardavide.Aura: 42\n"
                case "get_app_container":
                    stdout = str(container) + "\n"
                case _:
                    raise AssertionError(f"Unexpected native command: {command}")
            return subprocess.CompletedProcess(command, returncode=0, stdout=stdout, stderr="")

        def monotonic() -> float:
            return elapsed_seconds[0]

        def sleep(seconds: float) -> None:
            assert 0 < seconds <= 1
            elapsed_seconds[0] += 60

        monkeypatch.setattr(coverage_collect.subprocess, "run", run)
        monkeypatch.setattr(coverage_collect.time, "monotonic", monotonic)
        monkeypatch.setattr(coverage_collect.time, "sleep", sleep)

        # when
        with pytest.raises(ValueError, match="initial settings") as failure:
            coverage_collect.prepare_snapshot_host(products=products, simulator="prepared-simulator", root=tmp_path)

        # then
        assert 120 <= elapsed_seconds[0] <= 180
        assert [command[2] for command in native_commands] == [
            "list", "bootstatus", "install", "launch", "get_app_container", "terminate", "shutdown",
        ]
        assert plistlib.loads(preferences.read_bytes()) == {"theme": "system"}
        diagnostic = (tmp_path / "build/coverage-diagnostics/host-preparation-prepared-simulator.log").read_text()
        assert str(failure.value) in diagnostic, "Retained diagnostics must explain why native host initialization failed"

    def test_given_native_launch_and_shutdown_failures_when_preparing_host_then_preserves_primary_startup_failure_and_diagnostics(
        self: TestIosCollection,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect

        products = tmp_path / "Products"
        app = products / "Debug-iphonesimulator/Aura.app"
        app.mkdir(parents=True)
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "fardavide.Aura"}))
        launch_command = ("xcrun", "simctl", "launch", "--arch=arm64", "prepared-simulator", "fardavide.Aura")
        startup_failure = subprocess.CalledProcessError(
            returncode=71, cmd=launch_command, output="launch output\n", stderr="primary native startup failure\n",
        )
        native_commands: list[tuple[str, ...]] = []

        def run(
            command: Sequence[str],
            *,
            capture_output: bool = False,
            check: bool = False,
            cwd: Path | None = None,
            text: bool = False,
            timeout: float | None = None,
        ) -> subprocess.CompletedProcess[str]:
            assert tuple(command[:2]) == ("xcrun", "simctl")
            assert check is True
            native_commands.append(tuple(command))
            match command[2]:
                case "list":
                    stdout = json.dumps({"devices": {"ios-26-5": [
                        {"udid": "prepared-simulator", "state": "Shutdown"},
                    ]}})
                case "bootstatus" | "install":
                    stdout = ""
                case "launch":
                    assert tuple(command) == launch_command
                    raise startup_failure
                case "shutdown":
                    raise subprocess.CalledProcessError(
                        returncode=72, cmd=command, output="shutdown output\n", stderr="secondary cleanup failure\n",
                    )
                case _:
                    raise AssertionError(f"Unexpected native command after startup failure: {command}")
            return subprocess.CompletedProcess(command, returncode=0, stdout=stdout, stderr="")

        monkeypatch.setattr(coverage_collect.subprocess, "run", run)

        # when
        with pytest.raises(subprocess.CalledProcessError) as failure:
            coverage_collect.prepare_snapshot_host(products=products, simulator="prepared-simulator", root=tmp_path)

        # then
        assert failure.value is startup_failure, "Simulator cleanup must preserve the original native startup exception"
        assert failure.value.returncode == 71
        assert failure.value.stderr == "primary native startup failure\n"
        assert [command[2] for command in native_commands] == ["list", "bootstatus", "install", "launch", "shutdown"]
        diagnostic = (tmp_path / "build/coverage-diagnostics/host-preparation-prepared-simulator.log").read_text()
        assert "primary native startup failure" in diagnostic
        assert "secondary cleanup failure" in diagnostic

    @pytest.mark.parametrize("initial_state", ["Booted", "Shutdown"])
    def test_given_uninitialized_native_host_when_prepared_then_waits_for_app_settings_and_restores_initial_state(
        self: TestIosCollection,
        initial_state: Literal["Booted", "Shutdown"],
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect

        products = tmp_path / "Products"
        app = products / "Debug-iphonesimulator/Aura.app"
        app.mkdir(parents=True)
        (app / "Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "fardavide.Aura"}))
        (app / "Aura").write_bytes(b"compiled instrumented app")
        container = tmp_path / "Simulator/AppData"
        preferences = container / "Library/Preferences/fardavide.Aura.plist"
        native_commands: list[tuple[str, ...]] = []
        elapsed_seconds = [0.0]
        waits: list[float] = []

        def run(
            command: Sequence[str],
            *,
            capture_output: bool = False,
            check: bool = False,
            cwd: Path | None = None,
            text: bool = False,
            timeout: float | None = None,
        ) -> subprocess.CompletedProcess[str]:
            assert tuple(command[:2]) == ("xcrun", "simctl")
            assert check is True
            assert timeout is not None and 0 < timeout <= 180
            native_commands.append(tuple(command))
            match command[2]:
                case "list":
                    assert tuple(command[2:]) == ("list", "devices", "--json")
                    stdout = json.dumps({"devices": {"ios-26-5": [
                        {"udid": "unrelated-device", "state": "Booted" if initial_state == "Shutdown" else "Shutdown"},
                        {"udid": "prepared-simulator", "state": initial_state},
                    ]}})
                case "bootstatus":
                    assert tuple(command[3:]) == ("prepared-simulator", "-b")
                    stdout = ""
                case "install":
                    assert tuple(command[3:]) == ("prepared-simulator", str(app))
                    stdout = ""
                case "launch":
                    assert tuple(command[3:]) == ("--arch=arm64", "prepared-simulator", "fardavide.Aura")
                    assert not preferences.exists()
                    preferences.parent.mkdir(parents=True)
                    preferences.write_bytes(plistlib.dumps({"theme": "system"}))
                    stdout = "fardavide.Aura: 42\n"
                case "get_app_container":
                    assert tuple(command[3:]) == ("prepared-simulator", "fardavide.Aura", "data")
                    stdout = str(container) + "\n"
                case "terminate":
                    assert tuple(command[3:]) == ("prepared-simulator", "fardavide.Aura")
                    assert plistlib.loads(preferences.read_bytes()) == {"theme": "system", "dynamicCameraOrder": True}
                    stdout = ""
                case "shutdown":
                    assert initial_state == "Shutdown"
                    assert tuple(command[3:]) == ("prepared-simulator",)
                    stdout = ""
                case _:
                    raise AssertionError(f"Unexpected native command: {command}")
            return subprocess.CompletedProcess(command, returncode=0, stdout=stdout, stderr="")

        def monotonic() -> float:
            return elapsed_seconds[0]

        def sleep(seconds: float) -> None:
            waits.append(seconds)
            elapsed_seconds[0] += seconds
            preferences.write_bytes(plistlib.dumps({"theme": "system", "dynamicCameraOrder": True}))

        monkeypatch.setattr(coverage_collect.subprocess, "run", run)
        monkeypatch.setattr(coverage_collect.time, "monotonic", monotonic)
        monkeypatch.setattr(coverage_collect.time, "sleep", sleep)

        # when
        coverage_collect.prepare_snapshot_host(products=products, simulator="prepared-simulator", root=tmp_path)

        # then
        expected_commands = ["list", "bootstatus", "install", "launch", "get_app_container", "terminate"]
        if initial_state == "Shutdown":
            expected_commands.append("shutdown")
        assert [command[2] for command in native_commands] == expected_commands
        assert waits

    def test_given_instrumented_build_producer_when_built_then_enumerates_once_and_seals_plan_without_enumeration_counters(
        self: TestIosCollection,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect
        from coverage_artifacts import CollectionIdentity
        from coverage_inventory import JsonValue, decode_json
        from coverage_products import IosBuildStamp, source_digest

        for name in ("Aura/App.swift", "AuraKit/Sources/Entity.swift"):
            source = tmp_path / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("struct Source {}\n")
        derived = tmp_path / "derived"
        products = derived / "Build/Products"
        products.mkdir(parents=True)
        test_plan: JsonValue = {
            "AuraTests": {
                "BlueprintName": "AuraTests", "InProcessParallelizationEnabled": False,
                "IsAppHostedTestBundle": True, "ProductModuleName": "AuraTests",
            },
            "__xctestrun_metadata__": {"CodeCoverageBuildableInfos": [
                {"SourceFiles": ["App.swift"], "SourceFilesCommonPathPrefix": str(tmp_path / "Aura") + "/"},
                {"SourceFiles": ["Entity.swift"], "SourceFilesCommonPathPrefix": str(tmp_path / "AuraKit/Sources") + "/"},
            ]},
        }
        (products / "Aura.xctestrun").write_bytes(plistlib.dumps(test_plan))
        native_plan: JsonValue = {
            "errors": [],
            "values": [{"disabledTests": [], "enabledTests": [
                {"identifier": "AuraTests/Beta/two()"},
                {"identifier": "AuraTests/Alpha/one()"},
            ]}],
        }
        identity = CollectionIdentity(
            architecture="arm64", configuration="Debug-instrumented-v1", revision="a" * 40,
            run="local:producer", source_digest=source_digest(tmp_path), source_root=str(tmp_path),
            toolchain="Xcode 26 Swift 6",
        )
        stamp = IosBuildStamp(identity.architecture, identity.configuration, identity.source_digest, identity.toolchain)
        build_commands: list[tuple[str, ...]] = []
        enumeration_commands: list[tuple[str, ...]] = []
        simulator_commands: list[tuple[str, ...]] = []
        counters = (derived / "Build/ProfileData/enumeration.profraw", products / "default.profraw")

        def run_logged(command: tuple[str, ...], directory: Path, log: Path) -> None:
            assert command[:2] == ("xcodebuild", "build-for-testing")
            build_commands.append(command)

        def capture_json(command: tuple[str, ...], directory: Path, output: Path) -> JsonValue:
            assert len(build_commands) == 1
            assert "-enumerate-tests" in command
            assert command[command.index("-destination") + 1] == "platform=iOS Simulator,id=owned-enumeration-simulator"
            assert not (products / "coverage-build.json").exists()
            enumeration_commands.append(command)
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(native_plan))
            for counter in counters:
                counter.parent.mkdir(parents=True, exist_ok=True)
                counter.write_bytes(b"enumeration counters must not enter measured coverage")
            return native_plan

        def run(
            command: Sequence[str],
            *,
            capture_output: bool = False,
            check: bool = False,
            cwd: Path | None = None,
            text: bool = False,
            timeout: float | None = None,
        ) -> subprocess.CompletedProcess[str]:
            assert tuple(command[:2]) == ("xcrun", "simctl")
            simulator_commands.append(tuple(command))
            match command[2]:
                case "list":
                    stdout = json.dumps({"runtimes": [{
                        "identifier": "ios-26-5", "isAvailable": True, "name": "iOS 26.5", "version": "26.5",
                    }]})
                case "create":
                    stdout = "owned-enumeration-simulator\n"
                case "bootstatus":
                    assert tuple(command[3:]) == ("owned-enumeration-simulator", "-b")
                    assert check is True
                    assert timeout is not None and 0 < timeout <= 180
                    stdout = "Fully booted\n"
                case "shutdown" | "delete":
                    stdout = ""
                case _:
                    raise AssertionError(f"Unexpected simulator command: {command}")
            return subprocess.CompletedProcess(command, returncode=0, stdout=stdout, stderr="")

        monkeypatch.setattr(coverage_collect, "run_logged", run_logged)
        monkeypatch.setattr(coverage_collect, "capture_json", capture_json)
        monkeypatch.setattr(coverage_collect.subprocess, "run", run)

        # when
        coverage_collect.build_ios(derived=derived, identity=identity, root=tmp_path)

        # then
        assert len(enumeration_commands) == 1, "The build producer must discover the complete native test inventory once"
        assert coverage_collect.read_ios_enumeration(products=products, stamp=stamp) == native_plan
        assert decode_json((products / "coverage-build.json").read_text()) == asdict(stamp)
        assert [command[2] for command in simulator_commands] == ["list", "create", "bootstatus", "shutdown", "delete"]
        assert all(command[-1] == "owned-enumeration-simulator" for command in simulator_commands[-2:])
        assert all(not counter.exists() for counter in counters)

    @pytest.mark.parametrize(("tampering", "diagnostic"), [
        ("checksum", "identity or checksum"),
        ("stale-stamp", "identity or checksum"),
        ("missing", "regular files"),
        ("native-errors", "enumeration errors"),
    ])
    def test_given_altered_native_enumeration_when_read_then_rejects_invalid_producer_handoff(
        self: TestIosCollection,
        diagnostic: str,
        tampering: Literal["checksum", "stale-stamp", "missing", "native-errors"],
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect
        from coverage_inventory import JsonValue
        from coverage_products import IosBuildStamp

        plan: JsonValue = {
            "errors": [],
            "values": [{"disabledTests": [], "enabledTests": [
                {"identifier": "AuraTests/Beta/two()"},
                {"identifier": "AuraTests/Alpha/one()"},
            ]}],
        }
        stamp = IosBuildStamp("arm64", "Debug-instrumented-v1", "a" * 64, "Xcode 26 Swift 6")
        coverage_collect.write_ios_enumeration(products=tmp_path, plan=plan, stamp=stamp)
        payload = tmp_path / "coverage-enumerated-tests.json"
        expected_stamp = stamp
        match tampering:
            case "checksum":
                payload.write_bytes(payload.read_bytes() + b" ")
            case "stale-stamp":
                expected_stamp = IosBuildStamp("arm64", "Debug-instrumented-v1", "b" * 64, "Xcode 26 Swift 6")
            case "missing":
                payload.unlink()
            case "native-errors":
                payload.write_text(json.dumps({"errors": ["native enumeration failed"], "values": []}))
                (tmp_path / "coverage-enumeration.json").write_text(json.dumps({
                    "build_stamp": asdict(stamp),
                    "schema": 1,
                    "sha256": sha256(payload.read_bytes()).hexdigest(),
                }))

        # when
        with pytest.raises(ValueError, match=diagnostic):
            coverage_collect.read_ios_enumeration(products=tmp_path, stamp=expected_stamp)

        # then

    def test_given_sealed_producer_enumeration_when_collecting_then_initializes_host_and_clears_startup_counters_before_cases(
        self: TestIosCollection,
        monkeypatch: pytest.MonkeyPatch,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect
        from coverage_artifacts import CollectionIdentity
        from coverage_inventory import JsonValue, decode_json
        from coverage_products import IosBuildStamp, source_digest

        for name in ("Aura/App.swift", "AuraKit/Sources/Entity.swift"):
            source = tmp_path / name
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("struct Source {}\n")
        derived = tmp_path / "derived"
        products = derived / "Build/Products"
        products.mkdir(parents=True)
        test_plan: JsonValue = {
            "AuraTests": {
                "BlueprintName": "AuraTests", "InProcessParallelizationEnabled": False,
                "IsAppHostedTestBundle": True, "ProductModuleName": "AuraTests",
            },
            "__xctestrun_metadata__": {"CodeCoverageBuildableInfos": [
                {"SourceFiles": ["App.swift"], "SourceFilesCommonPathPrefix": str(tmp_path / "Aura") + "/"},
                {"SourceFiles": ["Entity.swift"], "SourceFilesCommonPathPrefix": str(tmp_path / "AuraKit/Sources") + "/"},
            ]},
        }
        (products / "Aura.xctestrun").write_bytes(plistlib.dumps(test_plan))
        native_plan: JsonValue = {
            "errors": [],
            "values": [{"disabledTests": [], "enabledTests": [
                {"identifier": "AuraTests/Beta/two()"},
                {"identifier": "AuraTests/Alpha/one()"},
            ]}],
        }
        identity = CollectionIdentity(
            architecture="arm64", configuration="Debug-instrumented-v1", revision="a" * 40,
            run="local:consumer", source_digest=source_digest(tmp_path), source_root=str(tmp_path),
            toolchain="Xcode 26 Swift 6",
        )
        stamp = IosBuildStamp(identity.architecture, identity.configuration, identity.source_digest, identity.toolchain)
        (products / "coverage-build.json").write_text(json.dumps(asdict(stamp)))
        coverage_collect.write_ios_enumeration(products=products, plan=native_plan, stamp=stamp)
        destination = tmp_path / "inputs/ios"
        captured_commands: list[tuple[str, ...]] = []
        case_commands: list[tuple[str, ...]] = []
        host_preparations: list[tuple[Path, str, Path]] = []
        startup_counter = derived / "Build/ProfileData/host-startup.profraw"

        class CaseExecutionReached(RuntimeError):
            pass

        def capture_json(command: tuple[str, ...], directory: Path, output: Path) -> JsonValue:
            captured_commands.append(command)
            raise AssertionError("The consumer must use the sealed producer plan instead of native discovery")

        def prepare_snapshot_host(products: Path, simulator: str, root: Path) -> None:
            host_preparations.append((products, simulator, root))
            startup_counter.parent.mkdir(parents=True, exist_ok=True)
            startup_counter.write_bytes(b"host startup counters must not enter required case coverage")

        def run_logged(command: tuple[str, ...], directory: Path, log: Path) -> None:
            assert decode_json((destination / "enumerated-tests.json").read_text()) == native_plan
            assert host_preparations == [(products, "consumer-simulator", tmp_path)], "Initialize the native host before required cases"
            assert not startup_counter.exists(), "Clear native host startup counters before required cases"
            case_commands.append(command)
            raise CaseExecutionReached()

        monkeypatch.setattr(coverage_collect, "capture_json", capture_json)
        monkeypatch.setattr(coverage_collect, "prepare_snapshot_host", prepare_snapshot_host, raising=False)
        monkeypatch.setattr(coverage_collect, "run_logged", run_logged)

        # when
        with pytest.raises(CaseExecutionReached):
            coverage_collect.collect_ios(
                derived=derived, destination=destination, identity=identity,
                root=tmp_path, shard=None, simulator="consumer-simulator",
            )

        # then
        assert captured_commands == []
        assert len(case_commands) == 1
        assert case_commands[0][:2] == ("xcodebuild", "test-without-building")
        assert "-enumerate-tests" not in case_commands[0]
        assert "-only-testing:AuraTests/Alpha" in case_commands[0]
        assert "-only-testing:AuraTests/Beta" in case_commands[0]

    @pytest.mark.parametrize("filename", ["coverage-enumerated-tests.json", "coverage-enumeration.json"])
    def test_given_enumeration_file_symlink_when_read_then_rejects_external_file_despite_matching_digest(
        self: TestIosCollection,
        filename: Literal["coverage-enumerated-tests.json", "coverage-enumeration.json"],
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect
        from coverage_inventory import JsonValue
        from coverage_products import IosBuildStamp

        plan: JsonValue = {
            "errors": [],
            "values": [{"disabledTests": [], "enabledTests": [
                {"identifier": "AuraTests/Beta/two()"},
                {"identifier": "AuraTests/Alpha/one()"},
            ]}],
        }
        products = tmp_path / "Products"
        products.mkdir()
        stamp = IosBuildStamp("arm64", "Debug-instrumented-v1", "a" * 64, "Xcode 26 Swift 6")
        coverage_collect.write_ios_enumeration(products=products, plan=plan, stamp=stamp)
        payload = products / filename
        external_payload = tmp_path / f"outside-{filename}"
        payload.rename(external_payload)
        payload.symlink_to(external_payload)

        # when
        with pytest.raises(ValueError, match="symlink|regular|unsafe"):
            coverage_collect.read_ios_enumeration(products=products, stamp=stamp)

        # then
        assert payload.is_symlink()

    def test_given_failed_native_enumeration_when_writing_then_emits_neither_payload_nor_success_receipt(
        self: TestIosCollection,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect
        from coverage_inventory import JsonValue
        from coverage_products import IosBuildStamp

        plan: JsonValue = {"errors": ["native enumeration failed"], "values": []}
        stamp = IosBuildStamp("arm64", "Debug-instrumented-v1", "a" * 64, "Xcode 26 Swift 6")

        # when
        with pytest.raises(ValueError, match="enumeration errors"):
            coverage_collect.write_ios_enumeration(products=tmp_path, plan=plan, stamp=stamp)

        # then
        assert not (tmp_path / "coverage-enumerated-tests.json").exists()
        assert not (tmp_path / "coverage-enumeration.json").exists()

    def test_given_complete_native_plan_when_handed_off_then_preserves_enumeration_with_build_identity_and_digest(
        self: TestIosCollection,
        tmp_path: Path,
    ) -> None:
        # given
        import coverage_collect
        from coverage_inventory import JsonValue, decode_json, enumerated_ios_tests
        from coverage_products import IosBuildStamp

        plan: JsonValue = {
            "errors": [],
            "values": [{"disabledTests": [], "enabledTests": [
                {"identifier": "AuraTests/Beta/two()"},
                {"identifier": "AuraTests/Alpha/one()"},
            ]}],
        }
        stamp = IosBuildStamp(
            architecture="arm64",
            configuration="Debug-instrumented-v1",
            source_digest="a" * 64,
            toolchain="Xcode 26 Swift 6",
        )

        # when
        coverage_collect.write_ios_enumeration(products=tmp_path, plan=plan, stamp=stamp)
        received = coverage_collect.read_ios_enumeration(products=tmp_path, stamp=stamp)

        # then
        assert received == plan
        assert enumerated_ios_tests(received) == ("AuraTests/Alpha/one()", "AuraTests/Beta/two()")
        enumeration_path = tmp_path / "coverage-enumerated-tests.json"
        assert decode_json(enumeration_path.read_text()) == plan
        assert decode_json((tmp_path / "coverage-enumeration.json").read_text()) == {
            "build_stamp": asdict(stamp),
            "schema": 1,
            "sha256": sha256(enumeration_path.read_bytes()).hexdigest(),
        }


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
