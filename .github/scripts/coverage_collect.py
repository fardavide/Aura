"""Collect raw coverage during Aura's required native executions."""

from pathlib import Path
import argparse
from collections.abc import Iterator, Mapping
from contextlib import contextmanager
import subprocess
import sys
from uuid import uuid4
from dataclasses import asdict
import json
import os
import platform
import plistlib
import shutil
import time
from hashlib import sha256
from coverage_artifacts import CollectionIdentity, validate_artifact, write_manifest
from coverage_inventory import JsonValue, IosRuntimeIdentity, balanced_shards, decode_json, enumerated_ios_tests, ios_runtime_identity, package_methods, verify_ios_tests, verify_package_events, verify_partition
from coverage_products import IosBuildStamp, archive_products, restore_products, source_digest, source_inventory, validate_ios_build_stamp, validate_mapping_inventory, xctestrun_sources
from coverage_report import Scope, measure_export


def clear_counters(directory: Path) -> None:
    for path in directory.rglob("*"):
        if path.is_file() and path.suffix in (".profraw", ".profdata"):
            path.unlink()


def prepare_local(root: Path) -> Path | None:
    build = root / "build"
    paths = tuple(
        build / name
        for name in (
            "coverage-context.json", "coverage-inputs", "coverage", "coverage-diagnostics",
            "ios-products.json", "ios-products.tar.gz",
        )
        if (build / name).exists() or (build / name).is_symlink()
    )
    if not paths:
        return None
    history = build / "coverage-history"
    if build.is_symlink() or history.is_symlink():
        raise ValueError("Local coverage output directories must not be symlinks")
    archive = history / str(uuid4())
    archive.mkdir(parents=True)
    for path in paths:
        path.rename(archive / path.name)
    return archive


def capture_json(
    command: tuple[str, ...],
    directory: Path,
    output: Path,
) -> JsonValue:
    result = subprocess.run(command, cwd=directory, check=False, capture_output=True, text=True)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(result.stdout)
    if result.returncode:
        output.with_suffix(output.suffix + ".stderr").write_text(result.stderr)
    elif result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    result.check_returncode()
    return decode_json(result.stdout)


def create_context(root: Path) -> CollectionIdentity:
    if platform.machine() != "arm64":
        raise ValueError("Aura coverage requires the verified arm64 toolchain")
    versions = tuple(
        subprocess.run(command, check=True, capture_output=True, text=True).stdout.strip()
        for command in (
            ("xcodebuild", "-version"), ("swift", "--version"),
            ("xcrun", "llvm-cov", "--version"),
            ("xcrun", "--sdk", "macosx", "--show-sdk-version"),
            ("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"),
        )
    )
    return CollectionIdentity(
        architecture="arm64", configuration="Debug-instrumented-v1",
        revision=subprocess.run(("git", "rev-parse", "HEAD"), cwd=root, check=True, capture_output=True, text=True).stdout.strip(),
        run=run_identity(os.environ), source_digest=source_digest(root), source_root=str(root),
        toolchain="\n".join(versions),
    )


def write_ios_enumeration(products: Path, plan: JsonValue, stamp: IosBuildStamp) -> None:
    enumerated_ios_tests(plan)
    content = (json.dumps(plan, indent=2, sort_keys=True) + "\n").encode()
    (products / "coverage-enumerated-tests.json").write_bytes(content)
    (products / "coverage-enumeration.json").write_text(json.dumps({
        "schema": 1, "build_stamp": asdict(stamp), "sha256": sha256(content).hexdigest(),
    }, indent=2, sort_keys=True) + "\n")


def read_ios_enumeration(products: Path, stamp: IosBuildStamp) -> JsonValue:
    for name in ("coverage-enumerated-tests.json", "coverage-enumeration.json"):
        path = products / name
        if path.is_symlink() or not path.is_file():
            raise ValueError("Compiled native enumeration must contain regular files without symlinks")
    content = (products / "coverage-enumerated-tests.json").read_bytes()
    receipt = decode_json((products / "coverage-enumeration.json").read_text())
    if not isinstance(receipt, dict) or type(receipt.get("schema")) is not int or receipt != {
        "schema": 1, "build_stamp": asdict(stamp), "sha256": sha256(content).hexdigest(),
    }:
        raise ValueError("Compiled native test enumeration identity or checksum differs")
    plan = decode_json(content.decode())
    enumerated_ios_tests(plan)
    return plan


@contextmanager
def snapshot_simulator(provided: str | None = None) -> Iterator[str]:
    if provided is not None:
        yield provided
        return
    runtime = snapshot_runtime(decode_json(subprocess.run(
        ("xcrun", "simctl", "list", "runtimes", "--json"), check=True, capture_output=True, text=True,
    ).stdout))
    simulator = subprocess.run(
        ("xcrun", "simctl", "create", f"AuraCoverage-{uuid4()}", "com.apple.CoreSimulator.SimDeviceType.iPhone-17", runtime),
        check=True, capture_output=True, text=True,
    ).stdout.strip()
    try:
        yield simulator
    finally:
        subprocess.run(("xcrun", "simctl", "shutdown", simulator), capture_output=True, text=True)
        subprocess.run(("xcrun", "simctl", "delete", simulator), check=True, capture_output=True, text=True)


def build_ios(
    derived: Path,
    identity: CollectionIdentity,
    root: Path,
) -> None:
    stamp = derived / "Build/Products/coverage-build.json"
    stamp.unlink(missing_ok=True)
    for name in ("coverage-enumerated-tests.json", "coverage-enumeration.json"):
        (stamp.parent / name).unlink(missing_ok=True)
    run_logged(command=(
        "xcodebuild", "build-for-testing", "-scheme", "Aura", "-destination", "generic/platform=iOS Simulator",
        "-derivedDataPath", str(derived), "-clonedSourcePackagesDirPath", str(root / "SourcePackages"),
        "-enableCodeCoverage", "YES", "ENABLE_CODE_COVERAGE=YES", "CLANG_COVERAGE_MAPPING=YES",
        "CODE_SIGN_IDENTITY=", "CODE_SIGNING_REQUIRED=NO", "CODE_SIGNING_ALLOWED=NO", "-jobs", "4", "-quiet",
    ), directory=root, log=root / "build/coverage-diagnostics/ios-build.log")
    plans = tuple((derived / "Build/Products").glob("*.xctestrun"))
    if len(plans) != 1:
        raise ValueError("iOS instrumented build must emit exactly one xctestrun")
    xctestrun_sources(root, decode_json(json.dumps(plistlib.loads(plans[0].read_bytes()))))
    clear_counters(derived)
    discovery_started = time.monotonic()
    with snapshot_simulator() as simulator:
        native_plan = capture_json(command=(
            "xcodebuild", "test-without-building", "-xctestrun", str(plans[0]), "-derivedDataPath", str(derived),
            "-destination", f"platform=iOS Simulator,id={simulator}", "-enumerate-tests",
            "-test-enumeration-style", "flat", "-test-enumeration-format", "json",
            "-test-enumeration-output-path", "-", "-parallel-testing-enabled", "NO", "-quiet",
        ), directory=root, output=root / "build/coverage-diagnostics/ios-enumeration.json")
    print(f"Native iOS inventory discovery: {time.monotonic() - discovery_started:.3f}s", flush=True)
    clear_counters(derived)
    if source_digest(root) != identity.source_digest:
        raise ValueError("Source changed while building iOS products")
    identity_stamp = IosBuildStamp(
        architecture=identity.architecture, configuration=identity.configuration,
        source_digest=identity.source_digest, toolchain=identity.toolchain,
    )
    write_ios_enumeration(stamp.parent, native_plan, identity_stamp)
    stamp.write_text(json.dumps(asdict(identity_stamp), indent=2, sort_keys=True))


def prepare_snapshot_host(products: Path, simulator: str, root: Path) -> None:
    # Native discovery used to initialize the app on each consumer simulator.
    # Preserve that state without repeating discovery or collecting its counters.
    app = products / "Debug-iphonesimulator/Aura.app"
    info = decode_json(json.dumps(plistlib.loads((app / "Info.plist").read_bytes())))
    if not isinstance(info, dict) or info.get("CFBundleIdentifier") != "fardavide.Aura":
        raise ValueError("Snapshot host must be the matching compiled Aura app")
    bundle = "fardavide.Aura"
    log = root / "build/coverage-diagnostics" / f"host-preparation-{simulator}.log"
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()

    def native(*arguments: str) -> str:
        command = ("xcrun", "simctl", *arguments)
        with log.open("a") as receipt:
            receipt.write(f"{command!r}\n")
            try:
                result = subprocess.run(command, cwd=root, check=True, capture_output=True, text=True, timeout=180)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as error:
                for output in (error.stdout, error.stderr):
                    if isinstance(output, bytes):
                        receipt.write(output.decode(errors="replace"))
                    elif isinstance(output, str):
                        receipt.write(output)
                raise
            receipt.write(result.stdout)
            receipt.write(result.stderr)
        return result.stdout

    inventory = decode_json(native("list", "devices", "--json"))
    if not isinstance(inventory, dict) or not isinstance(inventory.get("devices"), dict):
        raise ValueError("Missing snapshot preparation simulator inventory")
    devices = inventory["devices"]
    assert isinstance(devices, dict)
    states: list[JsonValue] = []
    for group in devices.values():
        if not isinstance(group, list):
            raise ValueError("Invalid snapshot preparation simulator inventory")
        for device in group:
            if not isinstance(device, dict):
                raise ValueError("Invalid snapshot preparation device")
            if device.get("udid") == simulator:
                states.append(device.get("state"))
    if len(states) != 1 or states[0] not in ("Booted", "Shutdown"):
        raise ValueError("Snapshot preparation requires one Booted or Shutdown simulator")
    launched = False
    try:
        native("bootstatus", simulator, "-b")
        native("install", simulator, str(app))
        native("launch", "--arch=arm64", simulator, bundle)
        launched = True
        container = Path(native("get_app_container", simulator, bundle, "data").strip())
        if not container.is_absolute() or not container.is_dir():
            raise ValueError("Missing native snapshot host data container")
        preferences = container / "Library/Preferences" / f"{bundle}.plist"
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            if preferences.is_file():
                settings = decode_json(json.dumps(plistlib.loads(preferences.read_bytes())))
                if not isinstance(settings, dict):
                    raise ValueError("Invalid native snapshot host settings")
                if settings.get("theme") == "system" and settings.get("dynamicCameraOrder") is True:
                    break
            time.sleep(0.25)
        else:
            raise ValueError("Native snapshot host did not persist its initial settings")
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        with log.open("a") as receipt:
            receipt.write(f"Native snapshot host preparation failed: {error}\n")
        raise
    finally:
        original_error = sys.exception()
        cleanup_failure: OSError | subprocess.SubprocessError | None = None
        cleanup_commands: list[tuple[str, ...]] = []
        if launched:
            cleanup_commands.append(("terminate", simulator, bundle))
        if states[0] == "Shutdown":
            cleanup_commands.append(("shutdown", simulator))
        for command in cleanup_commands:
            try:
                native(*command)
            except (OSError, subprocess.SubprocessError) as error:
                if original_error is not None:
                    original_error.add_note(f"Snapshot host cleanup also failed: {error}")
                elif cleanup_failure is not None:
                    cleanup_failure.add_note(f"Snapshot host cleanup also failed: {error}")
                else:
                    cleanup_failure = error
        if cleanup_failure is not None:
            raise cleanup_failure
    print(f"Native iOS host preparation: {time.monotonic() - started:.3f}s", flush=True)


def collect_ios(
    derived: Path,
    destination: Path,
    identity: CollectionIdentity,
    root: Path,
    shard: int | None,
    simulator: str,
) -> None:
    if destination.exists():
        raise ValueError(f"Collection destination must be fresh: {destination}")
    products = derived / "Build/Products"
    stamp = IosBuildStamp(architecture=identity.architecture, configuration=identity.configuration, source_digest=identity.source_digest, toolchain=identity.toolchain)
    validate_ios_build_stamp(expected=stamp, stored=decode_json((products / "coverage-build.json").read_text()))
    plans = tuple(products.glob("*.xctestrun"))
    if len(plans) != 1:
        raise ValueError("iOS collection requires exactly one xctestrun")
    xctestrun_sources(root, decode_json(json.dumps(plistlib.loads(plans[0].read_bytes()))))
    native_plan = read_ios_enumeration(products, stamp)
    destination.mkdir(parents=True)
    shutil.copy2(products / "coverage-enumerated-tests.json", destination / "enumerated-tests.json")
    all_methods = enumerated_ios_tests(native_plan)
    methods = all_methods
    if shard is not None:
        weights = decode_json((root / ".github/coverage/ios-suite-durations.json").read_text())
        if not isinstance(weights, dict) or not isinstance(weights.get("weights"), dict):
            raise ValueError("Missing measured snapshot suite durations")
        durations = weights["weights"]
        assert isinstance(durations, dict)
        typed_durations: dict[str, float] = {}
        for suite, duration in durations.items():
            if type(duration) not in (float, int):
                raise ValueError("Snapshot duration must be numeric")
            assert isinstance(duration, (int, float))
            typed_durations[suite] = float(duration)
        if shard not in (0, 1):
            raise ValueError("iOS shard must be 0 or 1")
        methods = balanced_shards(expected=all_methods, durations=typed_durations)[shard]
    prepare_snapshot_host(products=products, simulator=simulator, root=root)
    clear_counters(derived)
    result = root / "build/coverage-diagnostics" / f"{destination.name}.xcresult"
    if result.exists():
        raise ValueError(f"Native result destination must be fresh: {result}")
    suites = tuple(sorted({method.split("/")[1] for method in methods}))
    run_logged(command=ios_test_command(derived=derived, destination=f"platform=iOS Simulator,id={simulator}", plan=plans[0], result=result, suites=suites), directory=root, log=destination / "tests.log")
    summary = capture_json(command=("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result), "--compact"), directory=root, output=destination / "test-summary.json")
    inventory = capture_json(command=("xcrun", "xcresulttool", "get", "test-results", "tests", "--path", str(result), "--compact"), directory=root, output=destination / "test-inventory.json")
    completed = verify_ios_tests(methods, inventory, summary)
    (destination / "planned-tests.json").write_text(json.dumps(methods))
    (destination / "completed-tests.json").write_text(json.dumps(completed))
    profiles = tuple((derived / "Build/ProfileData").rglob("*.profraw"))
    if not profiles:
        raise ValueError("iOS execution emitted no fresh raw coverage profiles")
    subprocess.run(("xcrun", "llvm-profdata", "merge", "-sparse", *(str(path) for path in profiles), "-o", str(destination / "profile.profdata")), check=True)
    objects = tuple(sorted({path.resolve() for path in products.rglob("*") if path.is_file() and b"__llvm_covmap" in path.read_bytes()}))
    seal_collection(destination=destination, identity=identity, objects=objects, platform_name="iOS Simulator", root=root, suite=f"ios-{shard}" if shard is not None else "ios")


def collect_package(
    destination: Path,
    identity: CollectionIdentity,
    root: Path,
) -> None:
    destination = (root / destination).resolve()
    if destination.exists():
        raise ValueError(f"Collection destination must be fresh: {destination}")
    destination.mkdir(parents=True)
    package = root / "AuraKit"
    clear_counters(package / ".build")
    (package / "default.profraw").unlink(missing_ok=True)
    # Build instrumentation before independent enumeration; execution happens once below.
    run_logged(command=("swift", "build", "--build-tests", "--enable-code-coverage", "--jobs", "4"), directory=package, log=root / "build/coverage-diagnostics/package-build.log")
    listing = subprocess.run(("swift", "test", "list", "--skip-build", "--enable-code-coverage"), cwd=package, check=True, capture_output=True, text=True).stdout
    methods = package_methods(listing)
    (destination / "enumerated-tests.json").write_text(json.dumps(methods))
    clear_counters(package / ".build")
    (package / "default.profraw").unlink(missing_ok=True)
    command, directory = package_test_command(events=destination / "native-events.jsonl", root=root)
    run_logged(command=command, directory=directory, log=destination / "tests.log")
    planned, completed = verify_package_events(methods, tuple(decode_json(line) for line in (destination / "native-events.jsonl").read_text().splitlines() if line.strip()))
    (destination / "planned-tests.json").write_text(json.dumps(planned))
    (destination / "completed-tests.json").write_text(json.dumps(completed))
    binaries = Path(subprocess.run(("swift", "build", "--show-bin-path"), cwd=package, check=True, capture_output=True, text=True).stdout.strip())
    objects: list[Path] = []
    for target in sorted({method.split(".", 1)[0] for method in methods}):
        candidates = [path for path in binaries.rglob("*") if path.is_file() and path.name in (target, f"{target}.xctest")]
        if not candidates:
            # SwiftPM's native driver links all targets into one package test executable.
            candidates = [path for path in binaries.glob("*PackageTests.xctest/Contents/MacOS/*") if path.is_file()]
            candidates.extend(path for path in binaries.glob("*PackageTests") if path.is_file())
        if not candidates:
            raise ValueError(f"Missing coverage mapping for package test target: {target}")
        objects.extend(candidates)
    profiles = tuple(sorted((package / ".build").rglob("*.profraw")))
    if not profiles:
        raise ValueError("Package execution emitted no fresh raw coverage profiles")
    subprocess.run(("xcrun", "llvm-profdata", "merge", "-sparse", *(str(path) for path in profiles), "-o", str(destination / "profile.profdata")), check=True)
    seal_collection(destination=destination, identity=identity, objects=tuple(sorted(set(objects))), platform_name="macOS", root=root, suite="package")


def seal_collection(
    destination: Path,
    identity: CollectionIdentity,
    objects: tuple[Path, ...],
    platform_name: str,
    root: Path,
    suite: str,
) -> None:
    if source_digest(root) != identity.source_digest:
        raise ValueError("Source changed during coverage collection")
    copied: list[Path] = []
    for index, binary in enumerate(objects):
        target = destination / "objects" / f"{index:03d}" / binary.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(binary, target)
        copied.append(target)
    if not copied:
        raise ValueError("Coverage collection emitted no mappings")
    result = subprocess.run(("xcrun", "llvm-cov", "export", str(copied[0]), *(f"--object={path}" for path in copied[1:]), "--empty-profile", "--summary-only", "--arch=arm64"), check=True, capture_output=True, text=True)
    if result.stderr.strip():
        raise ValueError(f"Coverage mapping diagnostics: {result.stderr}")
    scope = Scope.PACKAGE if suite == "package" else Scope.APP_HOSTED
    mapping = measure_export(decode_json(result.stdout), str(root), scope)
    validate_mapping_inventory(root, scope, mapping.files)
    sources = source_inventory(root)
    (destination / "source-inventory.json").write_text(json.dumps(sources))
    stamp: dict[str, JsonValue] = {
        "identity": asdict(identity), "mapping_sources": list(mapping.files),
        "objects": [str(path.relative_to(destination)) for path in copied],
        "platform": platform_name, "schema": 1, "sources": list(sources),
    }
    if suite == "package":
        tests = decode_json((destination / "enumerated-tests.json").read_text())
        if not isinstance(tests, list) or any(not isinstance(test, str) for test in tests):
            raise ValueError("Invalid package test target inventory")
        stamp["package_test_targets"] = sorted({test.split(".", 1)[0] for test in tests if isinstance(test, str)})
    (destination / "build-stamp.json").write_text(json.dumps(stamp, indent=2, sort_keys=True))
    write_manifest(destination, identity, suite)


def ios_test_command(
    derived: Path,
    destination: str,
    plan: Path,
    result: Path,
    suites: tuple[str, ...],
) -> tuple[str, ...]:
    return (
        "xcodebuild", "test-without-building", "-xctestrun", str(plan),
        "-destination", destination, "-derivedDataPath", str(derived),
        "-resultBundlePath", str(result), "-enableCodeCoverage", "YES",
        "-parallel-testing-enabled", "NO", "-jobs", "4",
        *(f"-only-testing:AuraTests/{suite}" for suite in suites),
    )


def package_test_command(
    events: Path,
    root: Path,
) -> tuple[tuple[str, ...], Path]:
    return (
        "swift", "test", "--jobs", "4", "--enable-code-coverage",
        "--experimental-event-stream-version", "0",
        "--event-stream-output-path", str(root / events),
    ), root / "AuraKit"


def run_logged(
    command: tuple[str, ...],
    directory: Path,
    log: Path,
) -> None:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("w") as receipt:
        process = subprocess.Popen(command, cwd=directory, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        assert process.stdout is not None
        for line in process.stdout:
            receipt.write(line)
            print(line, end="", flush=True)
        status = process.wait()
        if status:
            raise subprocess.CalledProcessError(status, command)


def run_identity(environment: Mapping[str, str]) -> str:
    if "GITHUB_RUN_ID" in environment:
        return f"github:{environment['GITHUB_RUN_ID']}:{environment['GITHUB_RUN_ATTEMPT']}"
    return f"local:{uuid4()}"


def snapshot_runtime(inventory: JsonValue) -> str:
    if not isinstance(inventory, dict) or not isinstance(inventory.get("runtimes"), list):
        raise ValueError("Simulator runtime inventory is invalid")
    candidates: list[tuple[tuple[int, ...], str]] = []
    for value in inventory["runtimes"]:
        if not isinstance(value, dict):
            raise ValueError("Simulator runtime must be an object")
        name, version, identifier = value.get("name"), value.get("version"), value.get("identifier")
        if value.get("isAvailable") is True and isinstance(name, str) and name.startswith("iOS 26"):
            if not isinstance(version, str) or not isinstance(identifier, str):
                raise ValueError("Simulator runtime identity is incomplete")
            candidates.append((tuple(int(part) for part in version.split(".")), identifier))
    if not candidates:
        raise ValueError("No available iOS 26 simulator runtime")
    return max(candidates)[1]


def read_context(path: Path) -> CollectionIdentity:
    value = decode_json(path.read_text())
    if not isinstance(value, dict):
        raise ValueError("Collection context must be an object")
    fields: dict[str, str] = {}
    for name in CollectionIdentity.__dataclass_fields__:
        field = value.get(name)
        if not isinstance(field, str):
            raise ValueError(f"Missing collection context {name}")
        fields[name] = field
    return CollectionIdentity(**fields)


def verify_ios_artifacts(inputs: Path, root: Path) -> None:
    if {path.name for path in inputs.iterdir()} != {"ios-0", "ios-1"}:
        raise ValueError("Snapshot verdict requires both isolated shard artifacts")
    plans: list[tuple[str, ...]] = []
    subsets: list[tuple[str, ...]] = []
    runtimes: list[IosRuntimeIdentity] = []
    common: dict[str, JsonValue] | None = None
    for suite in ("ios-0", "ios-1"):
        directory = inputs / suite
        manifest = decode_json((directory / "manifest.json").read_text())
        if not isinstance(manifest, dict) or not isinstance(manifest.get("identity"), dict):
            raise ValueError("Missing native snapshot artifact identity")
        fields = manifest["identity"]
        assert isinstance(fields, dict)
        source_root = fields.get("source_root")
        if not isinstance(source_root, str):
            raise ValueError("Missing snapshot source root")
        normalized = {key: value for key, value in fields.items() if key != "source_root"}
        if common is None:
            common = normalized
        if common != normalized or fields.get("source_digest") != source_digest(root):
            raise ValueError("Snapshot shard provenance differs from current source")
        if "GITHUB_RUN_ID" in os.environ and fields.get("run") != run_identity(os.environ):
            raise ValueError("Snapshot artifact is from another run attempt")
        revision = subprocess.run(("git", "rev-parse", "HEAD"), cwd=root, check=True, capture_output=True, text=True).stdout.strip()
        if fields.get("revision") != revision:
            raise ValueError("Snapshot artifact is from another revision")
        context: dict[str, str] = {}
        for key in CollectionIdentity.__dataclass_fields__:
            field = fields.get(key)
            if not isinstance(field, str):
                raise ValueError(f"Invalid snapshot context {key}")
            context[key] = field
        validate_artifact(directory / "manifest.json", CollectionIdentity(**context), suite)
        planned = decode_json((directory / "planned-tests.json").read_text())
        if not isinstance(planned, list) or any(not isinstance(test, str) for test in planned):
            raise ValueError("Invalid snapshot plan")
        methods = tuple(test for test in planned if isinstance(test, str) and "#case:" not in test)
        summary = decode_json((directory / "test-summary.json").read_text())
        runtimes.append(ios_runtime_identity(summary))
        completed = verify_ios_tests(methods, decode_json((directory / "test-inventory.json").read_text()), summary)
        if completed != tuple(planned) or decode_json((directory / "completed-tests.json").read_text()) != list(completed):
            raise ValueError("Snapshot native receipts differ from planned cases")
        plans.append(enumerated_ios_tests(decode_json((directory / "enumerated-tests.json").read_text())))
        subsets.append(methods)
    if plans[0] != plans[1]:
        raise ValueError("Snapshot native enumerations differ")
    if runtimes[0] != runtimes[1]:
        raise ValueError("Snapshot shard runtime versions or builds differ")
    verify_partition(plans[0], subsets)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("context", "package", "ios-build", "ios", "verify-ios", "products", "restore-products", "prepare-local"))
    parser.add_argument("--context", default=Path("build/coverage-context.json"), type=Path)
    parser.add_argument("--derived", default=Path("build/derived/ios"), type=Path)
    parser.add_argument("--inputs", default=Path("build/coverage-inputs"), type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--shard", choices=(0, 1), type=int)
    parser.add_argument("--simulator")
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    try:
        if arguments.action == "prepare-local":
            archive = prepare_local(root)
            if archive is not None:
                print(f"Previous local coverage evidence preserved in {archive}")
        elif arguments.action == "context":
            output = arguments.output or arguments.context
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(asdict(create_context(root)), indent=2, sort_keys=True))
        elif arguments.action == "verify-ios":
            verify_ios_artifacts(arguments.inputs, root)
        else:
            identity = read_context(arguments.context)
            if identity.source_digest != source_digest(root):
                raise ValueError("Collection context source changed; initialize a new collection")
            if arguments.action == "package":
                collect_package(destination=arguments.inputs / "package", identity=identity, root=root)
            elif arguments.action == "ios-build":
                build_ios(derived=arguments.derived, identity=identity, root=root)
            elif arguments.action == "ios":
                with snapshot_simulator(arguments.simulator) as simulator:
                    collect_ios(derived=arguments.derived, destination=arguments.inputs / (f"ios-{arguments.shard}" if arguments.shard is not None else "ios"), identity=identity, root=root, shard=arguments.shard, simulator=simulator)
            elif arguments.action == "products":
                archive = archive_products(source=arguments.derived / "Build/Products", destination=root / "build/ios-products.tar.gz")
                (root / "build/ios-products.json").write_text(json.dumps({"sha256": archive.sha256, "identity": asdict(identity)}, indent=2, sort_keys=True))
            elif arguments.action == "restore-products":
                metadata = decode_json((root / "build/ios-products.json").read_text())
                if not isinstance(metadata, dict) or not isinstance(metadata.get("sha256"), str) or not isinstance(metadata.get("identity"), dict):
                    raise ValueError("Missing compiled product provenance")
                stored = metadata["identity"]
                assert isinstance(stored, dict)
                if stored.get("source_root") != str(root):
                    raise ValueError("Compiled source root is incompatible with this checkout's snapshot baselines")
                if any(stored.get(key) != getattr(identity, key) for key in ("architecture", "configuration", "revision", "run", "source_digest", "toolchain")):
                    raise ValueError("Compiled products are incompatible with this collection")
                checksum = metadata["sha256"]
                assert isinstance(checksum, str)
                restore_products(archive=root / "build/ios-products.tar.gz", destination=arguments.derived / "Build/Products", expected_sha256=checksum)
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"Coverage collection failed: {error}", file=sys.stderr)
        return error.returncode if isinstance(error, subprocess.CalledProcessError) and error.returncode > 0 else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
