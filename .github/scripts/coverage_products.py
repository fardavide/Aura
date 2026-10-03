"""Source fingerprints and portable compiled products for coverage collection."""

from __future__ import annotations

import argparse
import json
import os
import posixpath
import re
import subprocess
import tarfile
import xml.etree.ElementTree as ElementTree
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from hashlib import sha256
from pathlib import Path, PurePosixPath
from typing import BinaryIO

from coverage_inventory import JsonValue, decode_json
from coverage_report import Scope


@dataclass(frozen=True)
class IosBuildStamp:
    architecture: str
    configuration: str
    source_digest: str
    toolchain: str

    def __post_init__(self: IosBuildStamp) -> None:
        if any(not isinstance(value, str) or not value.strip() for value in (
            self.architecture, self.configuration, self.source_digest, self.toolchain,
        )) or not re.fullmatch(r"[0-9a-f]{64}", self.source_digest):
            raise ValueError("iOS build stamp identity is incomplete or malformed")


@dataclass(frozen=True)
class ProductArchive:
    path: Path
    sha256: str
    members: tuple[str, ...]


@dataclass(frozen=True)
class ApplicationReference:
    collection_revision: str
    revision: str
    source_digest: str
    verified_files: tuple[str, ...]


def verify_application_reference(root: Path, revision: str) -> ApplicationReference:
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("Application reference must be a full commit SHA")
    object_type = subprocess.run(
        ("git", "cat-file", "-t", revision), cwd=root, capture_output=True, check=True, text=True,
    ).stdout.strip()
    if object_type != "commit":
        raise ValueError("Application reference must identify a commit")
    collection_revision = subprocess.run(
        ("git", "rev-parse", "HEAD"), cwd=root, capture_output=True, check=True, text=True,
    ).stdout.strip()
    reference = _committed_application_inputs(root, revision)
    committed = _committed_application_inputs(root, collection_revision)
    current: dict[str, Path] = {}
    for name in ("Aura", "AuraKit", "AuraTests", "Aura.xcodeproj"):
        if (root / name).is_symlink():
            raise ValueError("Protected application root is a symlink")
        for directory, children, filenames in os.walk(root / name):
            for child in tuple(children):
                path = Path(directory) / child
                if not _protected_application_path(PurePosixPath(path.relative_to(root).as_posix())):
                    children.remove(child)
                elif path.is_symlink():
                    raise ValueError("Protected application directory is a symlink")
            for filename in filenames:
                path = Path(directory) / filename
                relative = path.relative_to(root).as_posix()
                if _protected_application_path(PurePosixPath(relative)):
                    if path.is_symlink() or not path.is_file():
                        raise ValueError("Protected application input is not a regular file")
                    current[relative] = path
    for name in ("project.yml", "project.yaml"):
        path = root / name
        if path.exists():
            if path.is_symlink() or not path.is_file():
                raise ValueError("Protected project definition is not a regular file")
            current[name] = path
    if not reference or set(current) != set(reference) or set(committed) != set(reference):
        raise ValueError("Application reference protected inventory differs")
    digest = sha256()
    app_scheme = "Aura.xcodeproj/xcshareddata/xcschemes/Aura.xcscheme"
    for name in reference:
        # Equal Git object IDs identify the same immutable blob. The scheme alone
        # permits the documented serialization normalization below.
        if name != app_scheme and reference[name] != committed[name]:
            raise ValueError(f"Application reference protected input differs: {name}")
    with subprocess.Popen(
        ("git", "cat-file", "--batch"), cwd=root,
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    ) as blobs:
        assert blobs.stdin is not None and blobs.stdout is not None
        try:
            for name in sorted(reference):
                size = _request_git_blob(blobs.stdin, blobs.stdout, reference[name])
                digest.update(name.encode())
                digest.update(b"\0")
                if name == app_scheme:
                    if size > 1024 * 1024:
                        raise ValueError("Application reference scheme is too large")
                    expected = _serial_application_scheme(blobs.stdout.read(size), require_serial=False)
                    if blobs.stdout.read(1) != b"\n":
                        raise ValueError("Application reference Git blob receipt is incomplete")
                    recorded_size = _request_git_blob(blobs.stdin, blobs.stdout, committed[name])
                    if recorded_size > 1024 * 1024:
                        raise ValueError("Application reference scheme is too large")
                    recorded = _serial_application_scheme(blobs.stdout.read(recorded_size), require_serial=False)
                    if blobs.stdout.read(1) != b"\n":
                        raise ValueError("Application reference Git blob receipt is incomplete")
                    actual = _serial_application_scheme(current[name].read_bytes(), require_serial=True)
                    if actual != expected or recorded != expected:
                        raise ValueError(f"Application reference protected input differs: {name}")
                    digest.update(len(actual).to_bytes(8, "big"))
                    digest.update(actual)
                else:
                    digest.update(size.to_bytes(8, "big"))
                    with current[name].open("rb") as working:
                        remaining = size
                        while remaining:
                            expected_chunk = blobs.stdout.read(min(remaining, 64 * 1024))
                            if not expected_chunk:
                                raise ValueError("Application reference Git blob receipt is incomplete")
                            actual_chunk = working.read(len(expected_chunk))
                            if actual_chunk != expected_chunk:
                                raise ValueError(f"Application reference protected input differs: {name}")
                            digest.update(actual_chunk)
                            remaining -= len(expected_chunk)
                        if working.read(1):
                            raise ValueError(f"Application reference protected input differs: {name}")
                    if blobs.stdout.read(1) != b"\n":
                        raise ValueError("Application reference Git blob receipt is incomplete")
            blobs.stdin.close()
            if blobs.wait(timeout=30) != 0:
                raise ValueError("Application reference Git blob verification failed")
        finally:
            if blobs.poll() is None:
                blobs.kill()
    return ApplicationReference(collection_revision, revision, digest.hexdigest(), tuple(sorted(reference)))


def _committed_application_inputs(root: Path, revision: str) -> dict[str, str]:
    tree = subprocess.run(
        ("git", "ls-tree", "-r", "-z", revision),
        cwd=root, capture_output=True, check=True,
    ).stdout
    objects: dict[str, str] = {}
    for record in tree.split(b"\0"):
        if not record:
            continue
        metadata, name_bytes = record.split(b"\t", 1)
        name = name_bytes.decode("utf-8")
        if not _protected_application_path(PurePosixPath(name)):
            continue
        mode, kind, object_id = metadata.decode("ascii").split()
        if kind != "blob" or mode not in ("100644", "100755"):
            raise ValueError("Application reference contains a non-regular protected input")
        objects[name] = object_id
    return objects


def _request_git_blob(requests: BinaryIO, payload: BinaryIO, expected_id: str) -> int:
    requests.write(f"{expected_id}\n".encode("ascii"))
    requests.flush()
    fields = payload.readline().decode("ascii").split()
    if len(fields) != 3:
        raise ValueError("Application reference Git blob receipt is incomplete")
    object_id, kind, size_text = fields
    size = int(size_text)
    if object_id != expected_id or kind != "blob" or size < 0:
        raise ValueError("Application reference Git blob receipt is invalid")
    return size


def _protected_application_path(path: PurePosixPath) -> bool:
    if path.as_posix() in ("project.yml", "project.yaml"):
        return True
    if not path.parts or path.parts[0] not in ("Aura", "AuraKit", "AuraTests", "Aura.xcodeproj"):
        return False
    excluded = {".build", ".git", "build", "Build", "SourcePackages", "ProfileData", "__SnapshotFailures__", "xcuserdata"}
    if any(part in excluded for part in path.parts) or path.name == ".DS_Store" or path.suffix in (".profraw", ".profdata", ".xcuserstate"):
        return False
    if ".swiftpm" in path.parts:
        index = path.parts.index(".swiftpm")
        # Keep the parent directories traversable as well as the shared package scheme.
        remaining = path.parts[index + 1:]
        if remaining[:min(len(remaining), 2)] != ("xcode", "xcshareddata")[:min(len(remaining), 2)]:
            return False
    return True


def _serial_application_scheme(content: bytes, require_serial: bool) -> bytes:
    try:
        scheme = ElementTree.fromstring(content)
    except ElementTree.ParseError as error:
        raise ValueError("Application reference scheme is malformed") from error
    for testable in scheme.findall(".//TestableReference"):
        value = testable.get("parallelizable")
        if value not in (None, "YES", "NO") or require_serial and value != "NO":
            raise ValueError("Application collection scheme must retain serial test execution")
        testable.set("parallelizable", "NO")
    return ElementTree.tostring(scheme)


def archive_products(source: Path, destination: Path) -> ProductArchive:
    source = source.resolve()
    members = sorted(member for member in source.rglob("*") if not _counter_path(PurePosixPath(member.relative_to(source).as_posix())))
    if not members:
        raise ValueError("compiled product inventory is empty")
    for member in members:
        _safe_path(member.relative_to(source).as_posix())
        if not (member.is_file() or member.is_dir() or member.is_symlink()):
            raise ValueError("unsafe special file in compiled products")
        if member.is_symlink():
            if member.readlink().is_absolute():
                raise ValueError("unsafe absolute product symlink")
            try:
                target = member.resolve(strict=True)
            except (OSError, RuntimeError) as error:
                raise ValueError("unsafe broken or cyclic product symlink") from error
            if not target.is_relative_to(source):
                raise ValueError("unsafe product symlink escapes archive root")
            if _counter_path(PurePosixPath(target.relative_to(source).as_posix())):
                raise ValueError("product symlink aliases excluded counter state")
    with destination.open("xb") as output:
        with tarfile.open(fileobj=output, mode="w:gz", dereference=False) as archive:
            for member in members:
                archive.add(member, arcname=member.relative_to(source).as_posix(), recursive=False)
    return ProductArchive(destination, _file_sha256(destination), tuple(member.relative_to(source).as_posix() for member in members))


def main(arguments: Sequence[str] | None = None, root: Path | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    archive = commands.add_parser("archive")
    archive.add_argument("--destination", required=True, type=Path)
    archive.add_argument("--source", required=True, type=Path)
    restore = commands.add_parser("restore")
    restore.add_argument("--archive", required=True, type=Path)
    restore.add_argument("--destination", required=True, type=Path)
    restore.add_argument("--sha256", required=True)
    reference = commands.add_parser("verify-reference")
    reference.add_argument("--revision", default=os.environ.get("AURA_COVERAGE_APPLICATION_REFERENCE"))
    reference.add_argument("--fetch-missing", action="store_true")
    options = parser.parse_args(list(arguments) if arguments is not None else None)
    if options.command == "verify-reference":
        revision: object = options.revision
        if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}", revision):
            raise ValueError("Application reference must be a full commit SHA")
        project = root if root is not None else Path(__file__).resolve().parents[2]
        available = subprocess.run(
            ("git", "cat-file", "-t", revision), cwd=project, capture_output=True, text=True,
        )
        if available.returncode != 0 and options.fetch_missing:
            subprocess.run(
                ("git", "fetch", "--no-tags", "--depth=1", "origin", revision),
                cwd=project, capture_output=True, check=True, text=True,
            )
        proof = verify_application_reference(project, revision)
        print(json.dumps({
            "collection_revision": proof.collection_revision,
            "revision": proof.revision,
            "schema": 1,
            "source_digest": proof.source_digest,
            "verified_files": list(proof.verified_files),
        }, sort_keys=True))
        return 0
    destination: object = options.destination
    if not isinstance(destination, Path):
        raise ValueError("compiled product archive paths are missing")
    if options.command == "archive":
        source: object = options.source
        if not isinstance(source, Path):
            raise ValueError("compiled product archive source is missing")
        result = archive_products(source, destination)
        print(json.dumps({"archive": str(result.path), "members": list(result.members), "schema": 1, "sha256": result.sha256}, sort_keys=True))
    elif options.command == "restore":
        path: object = options.archive
        checksum: object = options.sha256
        if not isinstance(path, Path) or not isinstance(checksum, str):
            raise ValueError("compiled product restore arguments are missing")
        restore_products(path, destination, checksum)
        print(json.dumps({"destination": str(destination), "schema": 1, "sha256": checksum}, sort_keys=True))
    else:
        raise ValueError("unsupported compiled product command")
    return 0


def restore_products(
    archive: Path,
    destination: Path,
    expected_sha256: str,
) -> None:
    if not re.fullmatch(r"[0-9a-f]{64}", expected_sha256) or _file_sha256(archive) != expected_sha256:
        raise ValueError("compiled product archive checksum does not match")
    if destination.is_symlink() or destination.exists() and (not destination.is_dir() or any(destination.iterdir())):
        raise ValueError("compiled product restore destination must be a new or empty directory")
    with tarfile.open(archive) as payload:
        members = {member.name: member for member in payload.getmembers()}
        if not members:
            raise ValueError("compiled product archive is empty")
        if len(members) != len(payload.getmembers()):
            raise ValueError("duplicate compiled product archive member")
        for member in members.values():
            path = _safe_path(member.name)
            if not (member.isfile() or member.isdir() or member.issym() or member.islnk()):
                raise ValueError("unsafe special file in compiled product archive")
            if _counter_path(path):
                raise ValueError("compiled product archive contains counter state")
            for parent in path.parents:
                ancestor = members.get(parent.as_posix())
                if ancestor is not None and not ancestor.isdir():
                    raise ValueError("unsafe compiled product path traverses a non-directory member")
            if member.issym() or member.islnk():
                target = _archive_link_target(member.name, members)
                if _counter_path(target):
                    raise ValueError("compiled product link aliases counter state")
        payload.extractall(destination, filter="data")


def source_digest(root: Path) -> str:
    excluded = {".ai", ".build", ".git", ".venv-coverage", "build", "Build", "SourcePackages", "ProfileData", "__SnapshotFailures__", "xcuserdata"}
    inputs: list[Path] = []
    for name in ("Aura", "AuraKit", "AuraTests", "Aura.xcodeproj"):
        for directory, children, files in os.walk(root / name):
            children[:] = [child for child in children if child not in excluded]
            for filename in files:
                path = Path(directory) / filename
                parts = path.relative_to(root).parts
                if ".swiftpm" in parts:
                    index = parts.index(".swiftpm")
                    if parts[index + 1:index + 3] != ("xcode", "xcshareddata"):
                        continue
                if filename != ".DS_Store" and path.suffix not in (".profraw", ".profdata", ".xcuserstate"):
                    inputs.append(path)
    inputs.extend(root / name for name in ("Makefile", "project.yml", "project.yaml") if (root / name).is_file())
    digest = sha256()
    for path in sorted(inputs):
        content = path.read_bytes()
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(b"\0")
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return digest.hexdigest()


def source_inventory(root: Path) -> tuple[str, ...]:
    sources = tuple(sorted(
        path.relative_to(root).as_posix()
        for directory in (root / "Aura", root / "AuraKit/Sources")
        for path in directory.rglob("*.swift")
        if path.is_file()
    ))
    if not sources:
        raise ValueError("production source inventory is empty")
    return sources


def validate_mapping_inventory(
    root: Path,
    scope: Scope,
    mapped: Sequence[str],
) -> tuple[str, ...]:
    expected = {
        source for source in source_inventory(root)
        if scope != Scope.PACKAGE or source.startswith("AuraKit/Sources/")
    }
    if not set(mapped).issubset(expected) or len(mapped) != len(set(mapped)):
        raise ValueError("Invalid mapping source inventory; missing LLVM mapping for scoped production sources")
    unmapped = expected - set(mapped)
    ledger = root / ".github/coverage/unmapped-sources.json"
    if not ledger.exists():
        if unmapped:
            raise ValueError(f"Unclassified production source missing LLVM mapping: {sorted(unmapped)}")
        return ()
    document = decode_json(ledger.read_text())
    if not isinstance(document, dict) or set(document) != {"schema", "entries"} or type(document.get("schema")) is not int or document.get("schema") != 1:
        raise ValueError("Invalid unmapped source classification schema")
    entries = document.get("entries")
    if not isinstance(entries, list):
        raise ValueError("Unmapped source classifications must be a list")
    classified: dict[str, str] = {}
    seen: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"path", "sha256", "reason", "scopes"}:
            raise ValueError("Invalid unmapped source classification")
        path, digest, reason, scopes = entry["path"], entry["sha256"], entry["reason"], entry["scopes"]
        if not isinstance(path, str) or path in seen or not path.startswith(("Aura/", "AuraKit/Sources/")) or not path.endswith(".swift"):
            raise ValueError("Invalid or duplicate unmapped source path")
        _safe_path(path)
        seen.add(path)
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest) or not isinstance(reason, str) or not reason.strip():
            raise ValueError("Unmapped source requires a reviewed hash and reason")
        if not isinstance(scopes, list) or not scopes or any(
            not isinstance(value, str) or value not in {category.value for category in Scope}
            for value in scopes
        ) or len(scopes) != len(set(scopes)):
            raise ValueError("Invalid unmapped source classification scopes")
        if scope.value in scopes:
            classified[path] = digest
    if set(classified) != unmapped:
        raise ValueError(f"Unclassified or changed production source missing LLVM mapping: {sorted(unmapped ^ set(classified))}")
    for path, digest in classified.items():
        if (root / path).is_symlink() or _file_sha256(root / path) != digest:
            raise ValueError(f"Reviewed unmapped source content changed: {path}")
    return tuple(sorted(unmapped))


def validate_ios_build_stamp(expected: IosBuildStamp, stored: JsonValue) -> None:
    expected_fields: dict[str, JsonValue] = {
        "architecture": expected.architecture,
        "configuration": expected.configuration,
        "source_digest": expected.source_digest,
        "toolchain": expected.toolchain,
    }
    if stored != expected_fields:
        raise ValueError("iOS build stamp differs from current immutable build identity")


def xctestrun_sources(root: Path, plan: JsonValue) -> tuple[str, ...]:
    root = root.resolve()
    configuration = _object(plan, "xctestrun")
    if set(configuration) != {"AuraTests", "__xctestrun_metadata__"}:
        raise ValueError("xctestrun target inventory must contain only AuraTests")
    target = _object(configuration.get("AuraTests"), "xctestrun target")
    if target.get("InProcessParallelizationEnabled") is not False or target.get("IsAppHostedTestBundle") is not True or any(
        target.get(field) != "AuraTests" for field in ("BlueprintName", "ProductModuleName")
    ):
        raise ValueError("xctestrun target must be the serial app-hosted AuraTests bundle")
    metadata = _object(configuration.get("__xctestrun_metadata__"), "xctestrun metadata")
    infos = metadata.get("CodeCoverageBuildableInfos")
    if not isinstance(infos, list):
        raise ValueError("xctestrun coverage inventory must be a list")
    sources: list[str] = []
    for info in infos:
        fields = _object(info, "coverage buildable")
        prefix = fields.get("SourceFilesCommonPathPrefix")
        files = fields.get("SourceFiles")
        if not isinstance(prefix, str) or not isinstance(files, list):
            raise ValueError("coverage source inventory is malformed")
        for filename in files:
            if not isinstance(filename, str):
                raise ValueError("coverage source file must be a string")
            _safe_path(filename)
            # Xcode removes a common text prefix, which may end inside a filename.
            source = Path(prefix + filename)
            if not source.exists():
                raise ValueError(f"missing xctestrun mapping input: {source}")
            sources.append(source.relative_to(root).as_posix())
    production = {source for source in sources if source.endswith(".swift") and source.startswith(("Aura/", "AuraKit/Sources/"))}
    if production != set(source_inventory(root)):
        raise ValueError("xctestrun production file inventory differs from source inventory")
    return tuple(sorted(sources))


def _archive_link_target(
    name: str,
    members: Mapping[str, tarfile.TarInfo],
) -> PurePosixPath:
    current = PurePosixPath(name)
    followed: set[str] = set()
    while True:
        for index in range(1, len(current.parts) + 1):
            prefix = PurePosixPath(*current.parts[:index]).as_posix()
            member = members.get(prefix)
            if member is None or not (member.issym() or member.islnk()):
                continue
            if prefix in followed or PurePosixPath(member.linkname).is_absolute() or "\\" in member.linkname:
                raise ValueError("unsafe absolute or cyclic archive link")
            followed.add(prefix)
            base = PurePosixPath(member.name).parent if member.issym() else PurePosixPath(".")
            expanded = base / member.linkname / PurePosixPath(*current.parts[index:])
            current = PurePosixPath(posixpath.normpath(expanded.as_posix()))
            if current != PurePosixPath("."):
                _safe_path(current.as_posix())
            break
        else:
            if current != PurePosixPath(".") and current.as_posix() not in members:
                raise ValueError("unsafe broken archive link")
            return current


def _counter_path(path: PurePosixPath) -> bool:
    return path.suffix.lower() in (".profdata", ".profraw") or any(part.lower() in ("counters", "profiledata") for part in path.parts)


def _file_sha256(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as payload:
        while content := payload.read(1024 * 1024):
            digest.update(content)
    return digest.hexdigest()


def _object(value: JsonValue, label: str) -> dict[str, JsonValue]:
    if not isinstance(value, dict):
        raise ValueError(f"{label} must be an object")
    return value


def _safe_path(name: str) -> PurePosixPath:
    path = PurePosixPath(name)
    if not name or path.is_absolute() or "\\" in name or any(part in ("", ".", "..") for part in name.split("/")):
        raise ValueError(f"unsafe relative product path: {name}")
    return path


if __name__ == "__main__":
    raise SystemExit(main())
