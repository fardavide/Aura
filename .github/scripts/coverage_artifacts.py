from __future__ import annotations

from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path
import tempfile

JsonValue = bool | dict[str, "JsonValue"] | float | int | list["JsonValue"] | None | str

PAYLOAD_NAMES = frozenset({
    "build-stamp.json",
    "completed-tests.json",
    "enumerated-tests.json",
    "native-events.jsonl",
    "planned-tests.json",
    "profile.profdata",
    "source-inventory.json",
    "test-inventory.json",
    "test-summary.json",
    "tests.log",
})


@dataclass(frozen=True)
class CollectionIdentity:
    architecture: str
    configuration: str
    revision: str
    run: str
    source_digest: str
    source_root: str
    toolchain: str

    def __post_init__(self: CollectionIdentity) -> None:
        values = (
            self.architecture,
            self.configuration,
            self.revision,
            self.run,
            self.source_digest,
            self.source_root,
            self.toolchain,
        )
        if any(not isinstance(value, str) or not value.strip() for value in values):
            raise ValueError("collection identity fields must be nonempty strings")


@dataclass(frozen=True)
class ValidatedArtifact:
    identity: CollectionIdentity
    manifest_path: Path
    objects: tuple[Path, ...]
    profile: Path
    suite: str


def validate_artifact(
    manifest_path: Path,
    expected_identity: CollectionIdentity,
    expected_suite: str,
) -> ValidatedArtifact:
    actual_paths = _artifact_inventory(manifest_path.parent, manifest_path)
    manifest: JsonValue = json.loads(manifest_path.read_text(), object_pairs_hook=_unique_object)
    return _validate_contents(actual_paths, expected_identity, expected_suite, manifest, manifest_path)


def write_manifest(
    directory: Path,
    identity: CollectionIdentity,
    suite: str,
) -> Path:
    manifest_path = directory / "manifest.json"
    paths = _artifact_inventory(directory, manifest_path)
    manifest: dict[str, JsonValue] = {
        "complete": True,
        "files": [
            {
                "path": str(path.relative_to(directory)),
                "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            }
            for path in paths
        ],
        "identity": asdict(identity),
        "schema": 1,
        "suite": suite,
    }
    _validate_contents(paths, identity, suite, manifest, manifest_path)
    temporary_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            delete=False,
            dir=directory,
            mode="w",
            prefix=".manifest-",
        ) as stream:
            temporary_path = Path(stream.name)
            json.dump(manifest, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        temporary_path.replace(manifest_path)
    finally:
        if temporary_path is not None:
            temporary_path.unlink(missing_ok=True)
    return manifest_path


def _artifact_inventory(directory: Path, manifest_path: Path) -> tuple[Path, ...]:
    if directory.is_symlink() or manifest_path.is_symlink():
        raise ValueError("artifact cannot contain symlinks")
    files: list[Path] = []
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise ValueError("artifact cannot contain symlinks")
        if path.is_dir():
            if path.relative_to(directory).parts[0] != "objects":
                raise ValueError(f"unknown artifact directory: {path}")
        elif not path.is_file():
            raise ValueError(f"artifact payload must be a regular file: {path}")
        elif path != manifest_path:
            files.append(path)
    return tuple(files)


def _test_inventory(path: Path) -> frozenset[str]:
    inventory: JsonValue = json.loads(path.read_text(), object_pairs_hook=_unique_object)
    if not isinstance(inventory, list) or not inventory:
        raise ValueError(f"test inventory must be a nonempty list: {path}")
    tests: set[str] = set()
    for test in inventory:
        if not isinstance(test, str) or not test.strip() or test in tests:
            raise ValueError(f"test inventory must contain unique nonempty strings: {path}")
        tests.add(test)
    return frozenset(tests)


def _unique_object(pairs: list[tuple[str, JsonValue]]) -> dict[str, JsonValue]:
    result: dict[str, JsonValue] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON field: {key}")
        result[key] = value
    return result


def _validate_contents(
    actual_paths: tuple[Path, ...],
    expected_identity: CollectionIdentity,
    expected_suite: str,
    manifest: JsonValue,
    manifest_path: Path,
) -> ValidatedArtifact:
    directory = manifest_path.parent
    if (
        not isinstance(manifest, dict)
        or set(manifest) != {"complete", "files", "identity", "schema", "suite"}
        or type(manifest.get("schema")) is not int
        or manifest["schema"] != 1
    ):
        raise ValueError("unsupported artifact schema")
    if manifest.get("complete") is not True:
        raise ValueError("artifact collection is not complete")
    if (
        expected_suite not in ("package", "ios-0", "ios-1", "ios")
        or manifest.get("suite") != expected_suite
    ):
        raise ValueError("artifact suite does not match the required suite")
    if manifest.get("identity") != asdict(expected_identity):
        raise ValueError("artifact identity does not match this collection")
    files = manifest.get("files")
    if not isinstance(files, list):
        raise ValueError("artifact files must be an explicit inventory")
    declared: set[str] = set()
    for entry in files:
        if not isinstance(entry, dict) or set(entry) != {"path", "sha256"}:
            raise ValueError("invalid artifact file entry")
        name = entry["path"]
        checksum = entry["sha256"]
        if not isinstance(name, str) or not isinstance(checksum, str):
            raise ValueError("invalid artifact file entry")
        if (
            not name
            or "\\" in name
            or "\0" in name
            or name.startswith("/")
            or any(part in ("", ".", "..") for part in name.split("/"))
        ):
            raise ValueError(f"unsafe artifact path: {name}")
        if name in declared:
            raise ValueError(f"duplicate artifact file entry: {name}")
        if name not in PAYLOAD_NAMES and not name.startswith("objects/"):
            raise ValueError(f"unknown artifact payload or directory entry: {name}")
        if not (directory / name).is_file():
            raise ValueError(f"missing artifact payload or directory entry: {name}")
        if hashlib.sha256((directory / name).read_bytes()).hexdigest() != checksum:
            raise ValueError(f"artifact checksum mismatch: {name}")
        declared.add(name)
    actual = {str(path.relative_to(directory)) for path in actual_paths}
    if actual != declared:
        raise ValueError("artifact file inventory does not match declared files")
    objects = tuple(
        directory / name for name in sorted(declared) if name.startswith("objects/")
    )
    if (
        not {"completed-tests.json", "planned-tests.json", "profile.profdata"}.issubset(declared)
        or not objects
    ):
        raise ValueError("artifact is missing required profiles, objects, or test inventory")
    if any(path.stat().st_size == 0 for path in (*objects, directory / "profile.profdata")):
        raise ValueError("artifact coverage payload is empty")
    if (
        _test_inventory(directory / "planned-tests.json")
        != _test_inventory(directory / "completed-tests.json")
    ):
        raise ValueError("completed test inventory does not match the planned test inventory")
    return ValidatedArtifact(
        identity=expected_identity,
        manifest_path=manifest_path,
        objects=objects,
        profile=directory / "profile.profdata",
        suite=expected_suite,
    )
