from __future__ import annotations

import hashlib
import os
import subprocess
import sys
import tarfile
from pathlib import Path

import pytest

import coverage_products as products
from coverage_inventory import JsonValue, decode_json


@pytest.fixture
def project(tmp_path: Path) -> Path:
    for name in ("Aura/App.swift", "AuraKit/Sources/Entity.swift", "AuraKit/Tests/EntityTests.swift", "AuraKit/Package.swift", "AuraTests/__Snapshots__/image.png", "Aura.xcodeproj/project.pbxproj", "Aura.xcodeproj/xcshareddata/xcschemes/Aura.xcscheme", "Aura.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved", "Makefile", "project.yml"):
        path = tmp_path / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("input")
    return tmp_path


@pytest.fixture
def xctestrun(project: Path) -> dict[str, JsonValue]:
    return {
        "AuraTests": {"BlueprintName": "AuraTests", "InProcessParallelizationEnabled": False, "IsAppHostedTestBundle": True, "ProductModuleName": "AuraTests"},
        "__xctestrun_metadata__": {"CodeCoverageBuildableInfos": [
            {"SourceFiles": ["App.swift"], "SourceFilesCommonPathPrefix": str(project / "Aura")},
            {"SourceFiles": ["Entity.swift"], "SourceFilesCommonPathPrefix": str(project / "AuraKit/Sources")},
            {"SourceFiles": ["__Snapshots__/image.png"], "SourceFilesCommonPathPrefix": str(project / "AuraTests")},
        ]},
    }


class TestCoverageProducts:
    def test_given_valid_product_archive_when_restore_cli_runs_then_restores_checksum_verified_products(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        source.mkdir()
        (source / "binary").write_bytes(b"instrumented mapping")
        archive = products.archive_products(source, tmp_path / "products.tar.gz")
        destination = tmp_path / "restored"
        # when
        result = subprocess.run([
            sys.executable, products.__file__, "restore", "--archive", str(archive.path), "--destination", str(destination), "--sha256", archive.sha256,
        ], capture_output=True, check=False, text=True)
        # then
        assert result.returncode == 0, result.stderr
        assert (destination / "binary").read_bytes() == b"instrumented mapping"

    def test_given_compiled_products_when_archive_cli_runs_then_emits_checksum_metadata(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        source.mkdir()
        (source / "binary").write_bytes(b"instrumented mapping")
        destination = tmp_path / "products.tar.gz"
        # when
        result = subprocess.run([
            sys.executable, products.__file__, "archive", "--source", str(source), "--destination", str(destination),
        ], capture_output=True, check=False, text=True)
        # then
        assert result.returncode == 0, result.stderr
        assert decode_json(result.stdout) == {"archive": str(destination), "members": ["binary"], "schema": 1, "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()}

    def test_given_empty_product_archive_when_restored_then_rejects_missing_build(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        path = tmp_path / "empty.tar"
        with tarfile.open(path, "w"):
            pass
        # when
        with pytest.raises(ValueError, match="empty"):
            products.restore_products(path, tmp_path / "restored", hashlib.sha256(path.read_bytes()).hexdigest())
        # then

    def test_given_empty_products_when_archived_then_rejects_missing_build(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        source.mkdir()
        # when
        with pytest.raises(ValueError, match="empty"):
            products.archive_products(source, tmp_path / "products.tar.gz")
        # then

    def test_given_special_product_file_when_archived_then_rejects_before_writing(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        source.mkdir()
        os.mkfifo(source / "fifo")
        destination = tmp_path / "products.tar.gz"
        # when
        with pytest.raises(ValueError, match="unsafe"):
            products.archive_products(source, destination)
        # then
        assert not destination.exists()

    def test_given_special_archive_member_when_restored_then_rejects_before_any_output(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        path = tmp_path / "special.tar"
        with tarfile.open(path, "w") as archive:
            archive.addfile(tarfile.TarInfo("binary"))
            special = tarfile.TarInfo("fifo")
            special.type = tarfile.FIFOTYPE
            archive.addfile(special)
        destination = tmp_path / "restored"
        # when
        with pytest.raises(ValueError, match="unsafe"):
            products.restore_products(path, destination, hashlib.sha256(path.read_bytes()).hexdigest())
        # then
        assert not destination.exists()

    @pytest.mark.parametrize("kind", ["nonempty", "symlink"])
    def test_given_existing_or_aliased_destination_when_restored_then_rejects_reuse_without_removal(
        self: TestCoverageProducts,
        kind: str,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        source.mkdir()
        (source / "binary").write_bytes(b"mapping")
        archive = products.archive_products(source, tmp_path / "products.tar.gz")
        destination = tmp_path / "restored"
        if kind == "nonempty":
            destination.mkdir()
            (destination / "old.profraw").write_bytes(b"old counter")
        else:
            outside = tmp_path / "outside"
            outside.mkdir()
            destination.symlink_to(outside, target_is_directory=True)
        # when
        with pytest.raises(ValueError, match="destination"):
            products.restore_products(archive.path, destination, archive.sha256)
        # then
        assert not (destination / "binary").exists()

    @pytest.mark.parametrize("kind", ["file", "symlink"])
    def test_given_archive_member_through_non_directory_parent_when_restored_then_rejects_alias_write(
        self: TestCoverageProducts,
        kind: str,
        tmp_path: Path,
    ) -> None:
        # given
        path = tmp_path / "parents.tar"
        with tarfile.open(path, "w") as archive:
            directory = tarfile.TarInfo("directory")
            directory.type = tarfile.DIRTYPE
            archive.addfile(directory)
            parent = tarfile.TarInfo("alias")
            if kind == "symlink":
                parent.linkname = "directory"
                parent.type = tarfile.SYMTYPE
            archive.addfile(parent)
            archive.addfile(tarfile.TarInfo("alias/binary"))
        destination = tmp_path / "restored"
        # when
        with pytest.raises(ValueError, match="unsafe"):
            products.restore_products(path, destination, hashlib.sha256(path.read_bytes()).hexdigest())
        # then
        assert not destination.exists()

    def test_given_duplicate_archive_members_when_restored_then_rejects_ambiguous_products(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        path = tmp_path / "duplicate.tar"
        with tarfile.open(path, "w") as archive:
            archive.addfile(tarfile.TarInfo("binary"))
            archive.addfile(tarfile.TarInfo("binary"))
        destination = tmp_path / "restored"
        # when
        with pytest.raises(ValueError, match="duplicate"):
            products.restore_products(path, destination, hashlib.sha256(path.read_bytes()).hexdigest())
        # then
        assert not destination.exists()

    @pytest.mark.parametrize("target", ["../escape", "/absolute", "ProfileData/count", "missing"])
    def test_given_unsafe_archive_link_when_restored_then_rejects_before_any_output(
        self: TestCoverageProducts,
        target: str,
        tmp_path: Path,
    ) -> None:
        # given
        path = tmp_path / "links.tar"
        with tarfile.open(path, "w") as archive:
            archive.addfile(tarfile.TarInfo("binary"))
            link = tarfile.TarInfo("link")
            link.linkname = target
            link.type = tarfile.SYMTYPE
            archive.addfile(link)
        destination = tmp_path / "restored"
        checksum = hashlib.sha256(path.read_bytes()).hexdigest()
        # when
        with pytest.raises(ValueError, match="unsafe|counter"):
            products.restore_products(path, destination, checksum)
        # then
        assert not destination.exists()

    @pytest.mark.parametrize("name", ["../escape", "/absolute", "./binary", "binary//file", "bad\\file", "old.profraw", "ProfileData/count"])
    def test_given_unsafe_archive_member_when_restored_then_rejects_before_any_output(
        self: TestCoverageProducts,
        name: str,
        tmp_path: Path,
    ) -> None:
        # given
        path = tmp_path / "unsafe.tar"
        with tarfile.open(path, "w") as archive:
            archive.addfile(tarfile.TarInfo("binary"))
            archive.addfile(tarfile.TarInfo(name))
        destination = tmp_path / "restored"
        checksum = hashlib.sha256(path.read_bytes()).hexdigest()
        # when
        with pytest.raises(ValueError, match="unsafe|counter"):
            products.restore_products(path, destination, checksum)
        # then
        assert not destination.exists()

    def test_given_counter_alias_when_products_archived_then_rejects_hidden_counter_link(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        source.mkdir()
        (source / "old.profraw").write_bytes(b"counter")
        (source / "mapping").symlink_to("old.profraw")
        # when
        with pytest.raises(ValueError, match="counter"):
            products.archive_products(source, tmp_path / "products.tar.gz")
        # then

    @pytest.mark.parametrize("kind", ["absolute", "escape", "broken"])
    def test_given_nonportable_product_link_when_archived_then_rejects_before_writing(
        self: TestCoverageProducts,
        kind: str,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        source.mkdir()
        outside = tmp_path / "outside"
        outside.write_bytes(b"outside mapping")
        target = str(outside) if kind == "absolute" else "../outside" if kind == "escape" else "missing"
        (source / "link").symlink_to(target)
        destination = tmp_path / "products.tar.gz"
        # when
        with pytest.raises(ValueError, match="unsafe"):
            products.archive_products(source, destination)
        # then
        assert not destination.exists()

    @pytest.mark.parametrize("checksum", ["0" * 64, "", "bad"])
    def test_given_wrong_archive_checksum_when_restored_then_rejects_before_writing(
        self: TestCoverageProducts,
        checksum: str,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        source.mkdir()
        (source / "binary").write_bytes(b"mapping")
        archive = products.archive_products(source, tmp_path / "products.tar.gz")
        destination = tmp_path / "restored"
        # when
        with pytest.raises(ValueError, match="checksum"):
            products.restore_products(archive.path, destination, checksum)
        # then
        assert not destination.exists()

    def test_given_internal_framework_links_when_archive_restored_then_preserves_portable_links_and_modes(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        framework = source / "Kit.framework"
        binary = framework / "Versions/A/Kit"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"framework executable")
        binary.chmod(0o755)
        (framework / "Versions/Current").symlink_to("A")
        (framework / "Kit").symlink_to("Versions/Current/Kit")
        archive = products.archive_products(source, tmp_path / "products.tar.gz")
        destination = tmp_path / "restored"
        # when
        products.restore_products(archive.path, destination, archive.sha256)
        # then
        restored = destination / "Kit.framework/Kit"
        assert restored.is_symlink()
        assert restored.readlink().as_posix() == "Versions/Current/Kit"
        assert restored.read_bytes() == b"framework executable"
        assert restored.stat().st_mode & 0o111 == 0o111

    @pytest.mark.parametrize("counter", ["Build/ProfileData/a.profraw", "a.profdata", "Build/counters/count", "nested/a.profraw"])
    def test_given_existing_counters_when_products_archived_then_excludes_counter_state(
        self: TestCoverageProducts,
        counter: str,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        source.mkdir()
        (source / "executable").write_bytes(b"mapping")
        path = source / counter
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"stale counters")
        # when
        result = products.archive_products(source, tmp_path / "products.tar.gz")
        # then
        with tarfile.open(result.path) as archive:
            names = archive.getnames()
        assert counter not in names
        assert all("ProfileData" not in name and "counters" not in name for name in names)

    def test_given_compiled_products_when_archived_then_retains_executable_and_archive_checksum(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        source = tmp_path / "compiled"
        binary = source / "Aura.app/Aura"
        binary.parent.mkdir(parents=True)
        binary.write_bytes(b"instrumented executable")
        binary.chmod(0o755)
        archive = tmp_path / "products.tar.gz"
        # when
        result = products.archive_products(source, archive)
        # then
        assert result.path == archive
        assert result.sha256 == hashlib.sha256(archive.read_bytes()).hexdigest()
        assert result.members == ("Aura.app", "Aura.app/Aura")
        with tarfile.open(archive) as payload:
            assert payload.getmember("Aura.app/Aura").mode & 0o111 == 0o111

    def test_given_missing_mapping_input_when_xctestrun_validated_then_rejects_stale_metadata(
        self: TestCoverageProducts,
        project: Path,
        xctestrun: dict[str, JsonValue],
    ) -> None:
        # given
        (project / "AuraTests/__Snapshots__/image.png").unlink()
        # when
        with pytest.raises(ValueError, match="missing"):
            products.xctestrun_sources(project, xctestrun)
        # then

    @pytest.mark.parametrize("filename", ["../escape", "/escape", "", "./image.png", "a//image.png", "a\\image.png"])
    def test_given_unsafe_coverage_file_when_xctestrun_validated_then_rejects_path(
        self: TestCoverageProducts,
        filename: str,
        project: Path,
        xctestrun: dict[str, JsonValue],
    ) -> None:
        # given
        metadata = xctestrun["__xctestrun_metadata__"]
        assert isinstance(metadata, dict)
        infos = metadata["CodeCoverageBuildableInfos"]
        assert isinstance(infos, list)
        info = infos[-1]
        assert isinstance(info, dict)
        info["SourceFiles"] = [filename]
        # when
        with pytest.raises(ValueError, match="unsafe"):
            products.xctestrun_sources(project, xctestrun)
        # then

    def test_given_missing_production_mapping_when_xctestrun_validated_then_rejects_denominator_loss(
        self: TestCoverageProducts,
        project: Path,
        xctestrun: dict[str, JsonValue],
    ) -> None:
        # given
        metadata = xctestrun["__xctestrun_metadata__"]
        assert isinstance(metadata, dict)
        infos = metadata["CodeCoverageBuildableInfos"]
        assert isinstance(infos, list)
        infos.pop(0)
        # when
        with pytest.raises(ValueError, match="production"):
            products.xctestrun_sources(project, xctestrun)
        # then

    def test_given_additional_test_target_when_xctestrun_validated_then_rejects_scope_change(
        self: TestCoverageProducts,
        project: Path,
        xctestrun: dict[str, JsonValue],
    ) -> None:
        # given
        xctestrun["OtherTests"] = xctestrun["AuraTests"]
        # when
        with pytest.raises(ValueError, match="target"):
            products.xctestrun_sources(project, xctestrun)
        # then

    @pytest.mark.parametrize(("field", "value"), [("InProcessParallelizationEnabled", True), ("InProcessParallelizationEnabled", 0), ("InProcessParallelizationEnabled", None), ("BlueprintName", "OtherTests"), ("ProductModuleName", "OtherTests"), ("IsAppHostedTestBundle", False)])
    def test_given_unsafe_app_hosted_target_when_xctestrun_validated_then_rejects_target(
        self: TestCoverageProducts,
        field: str,
        project: Path,
        value: JsonValue,
        xctestrun: dict[str, JsonValue],
    ) -> None:
        # given
        target = xctestrun["AuraTests"]
        assert isinstance(target, dict)
        target[field] = value
        # when
        with pytest.raises(ValueError, match="target"):
            products.xctestrun_sources(project, xctestrun)
        # then

    def test_given_serial_app_hosted_xctestrun_when_validated_then_retains_mapping_file_inventory(
        self: TestCoverageProducts,
        project: Path,
        xctestrun: dict[str, JsonValue],
    ) -> None:
        # given
        # when
        result = products.xctestrun_sources(project, xctestrun)
        # then
        assert result == ("Aura/App.swift", "AuraKit/Sources/Entity.swift", "AuraTests/__Snapshots__/image.png")

    @pytest.mark.parametrize(("field", "value"), [("architecture", ""), ("configuration", " "), ("source_digest", "abc"), ("toolchain", "")])
    def test_given_invalid_ios_identity_when_stamp_constructed_then_rejects_identity(
        self: TestCoverageProducts,
        field: str,
        value: str,
    ) -> None:
        # given
        fields = {"architecture": "arm64", "configuration": "Debug", "source_digest": "a" * 64, "toolchain": "Xcode 27"}
        fields[field] = value
        # when
        with pytest.raises(ValueError, match="stamp"):
            products.IosBuildStamp(**fields)
        # then

    @pytest.mark.parametrize("field", ["architecture", "configuration", "source_digest", "toolchain"])
    def test_given_changed_ios_build_identity_when_reused_then_rejects_stamp(
        self: TestCoverageProducts,
        field: str,
    ) -> None:
        # given
        expected = products.IosBuildStamp("arm64", "Debug", "a" * 64, "Xcode 27")
        stored: dict[str, JsonValue] = {"architecture": "arm64", "configuration": "Debug", "source_digest": "a" * 64, "toolchain": "Xcode 27"}
        stored[field] = "different"
        # when
        with pytest.raises(ValueError, match="stamp"):
            products.validate_ios_build_stamp(expected, stored)
        # then

    def test_given_identical_ios_build_identity_when_reused_then_accepts_stamp(
        self: TestCoverageProducts,
    ) -> None:
        # given
        expected = products.IosBuildStamp("arm64", "Debug", "a" * 64, "Xcode 27 Swift 6.4 iOS 27 SDK")
        stored: JsonValue = {"architecture": "arm64", "configuration": "Debug", "source_digest": "a" * 64, "toolchain": "Xcode 27 Swift 6.4 iOS 27 SDK"}
        # when
        products.validate_ios_build_stamp(expected, stored)
        # then

    @pytest.mark.parametrize("name", ["AuraKit/.build/generated.swift", "AuraKit/build/output", "AuraKit/SourcePackages/pin", "AuraKit/.git/state", "AuraKit/.venv-coverage/python", "AuraKit/.ai/docs/state.md", "Aura.xcodeproj/xcuserdata/user.xcuserstate", "AuraTests/__SnapshotFailures__/failure.png", "AuraKit/.swiftpm/workspace-state.json", "AuraKit/Build/ProfileData/count.profraw"])
    def test_given_changed_generated_or_local_state_when_fingerprinted_then_digest_is_unchanged(
        self: TestCoverageProducts,
        name: str,
        project: Path,
    ) -> None:
        # given
        original = products.source_digest(project)
        path = project / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("local state")
        # when
        result = products.source_digest(project)
        # then
        assert result == original

    @pytest.mark.parametrize("name", ["Aura/App.swift", "AuraKit/Sources/Entity.swift", "AuraKit/Tests/EntityTests.swift", "AuraKit/Package.swift", "AuraTests/__Snapshots__/image.png", "Aura.xcodeproj/project.pbxproj", "Aura.xcodeproj/xcshareddata/xcschemes/Aura.xcscheme", "Aura.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved", "Makefile", "project.yml"])
    def test_given_changed_build_input_when_fingerprinted_then_digest_changes(
        self: TestCoverageProducts,
        name: str,
        project: Path,
    ) -> None:
        # given
        original = products.source_digest(project)
        (project / name).write_text("changed")
        # when
        result = products.source_digest(project)
        # then
        assert len(result) == 64
        assert result != original

    def test_given_no_production_swift_when_inventoried_then_rejects_empty_scope(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="source"):
            products.source_inventory(tmp_path)
        # then

    def test_given_production_and_test_sources_when_inventoried_then_only_production_swift_is_retained(
        self: TestCoverageProducts,
        tmp_path: Path,
    ) -> None:
        # given
        for name in ("Aura/App.swift", "Aura/Assets/image.png", "AuraKit/Sources/Domain/Entity.swift", "AuraKit/Tests/EntityTests.swift"):
            path = tmp_path / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("content")
        # when
        result = products.source_inventory(tmp_path)
        # then
        assert result == ("Aura/App.swift", "AuraKit/Sources/Domain/Entity.swift")
