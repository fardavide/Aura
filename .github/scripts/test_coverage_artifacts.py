from __future__ import annotations

from dataclasses import asdict, dataclass
import hashlib
import json
import os
from pathlib import Path

import pytest

from coverage_artifacts import CollectionIdentity, validate_artifact

JsonValue = bool | dict[str, "JsonValue"] | float | int | list["JsonValue"] | None | str


@dataclass
class ArtifactScenario:
    directory: Path
    identity: CollectionIdentity

    @property
    def manifest_path(self: ArtifactScenario) -> Path:
        return self.directory / "manifest.json"

    def manifest(self: ArtifactScenario) -> dict[str, JsonValue]:
        return {
            "complete": True,
            "files": [
                {"path": str(path.relative_to(self.directory)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                for path in sorted(self.directory.rglob("*"))
                if path.is_file() and path != self.manifest_path
            ],
            "identity": asdict(self.identity),
            "schema": 1,
            "suite": "package",
        }

    def save(self: ArtifactScenario, changes: dict[str, JsonValue] | None = None) -> None:
        manifest = self.manifest()
        manifest.update(changes or {})
        self.manifest_path.write_text(json.dumps(manifest))


@pytest.fixture
def artifact(tmp_path: Path) -> ArtifactScenario:
    identity = CollectionIdentity(
        architecture="arm64",
        configuration="Debug",
        revision="abc123",
        run="123-1",
        source_digest="source-hash",
        source_root="/checkout",
        toolchain="Xcode 26",
    )
    files = {
        "completed-tests.json": json.dumps(["Suite/test"]).encode(),
        "objects/Aura": b"binary-mapping",
        "planned-tests.json": json.dumps(["Suite/test"]).encode(),
        "profile.profdata": b"raw-profile",
    }
    for name, content in files.items():
        path = tmp_path / name
        path.parent.mkdir(exist_ok=True)
        path.write_bytes(content)
    scenario = ArtifactScenario(directory=tmp_path, identity=identity)
    scenario.save()
    return scenario


class TestCoverageArtifacts:
    @pytest.mark.parametrize("name", ["completed-tests.json", "objects/Aura", "planned-tests.json", "profile.profdata"])
    def test_given_changed_payload_when_validated_then_rejects_checksum_mismatch(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        name: str,
    ) -> None:
        # given
        (artifact.directory / name).write_bytes(b"tampered")
        # when
        with pytest.raises(ValueError, match="checksum"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    def test_given_complete_artifact_when_validated_then_returns_typed_inputs(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
    ) -> None:
        # given
        # when
        result = validate_artifact(artifact.manifest_path, artifact.identity, "package")

        # then
        assert result.profile == artifact.directory / "profile.profdata"
        assert result.objects == (artifact.directory / "objects/Aura",)
        assert result.manifest_path == artifact.manifest_path
        assert result.suite == "package"
        assert result.identity == artifact.identity

    def test_given_complete_collection_when_manifest_written_then_can_validate_artifact(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
    ) -> None:
        # given
        from coverage_artifacts import write_manifest

        artifact.manifest_path.unlink()
        # when
        manifest_path = write_manifest(artifact.directory, artifact.identity, "package")
        result = validate_artifact(manifest_path, artifact.identity, "package")
        # then
        assert result.manifest_path == artifact.manifest_path
        assert not tuple(artifact.directory.glob(".manifest-*"))

    def test_given_duplicate_file_entry_when_validated_then_rejects_inventory(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
    ) -> None:
        # given
        entries = artifact.manifest()["files"]
        assert isinstance(entries, list)
        artifact.save({"files": entries + [entries[0]]})
        # when
        with pytest.raises(ValueError, match="duplicate"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    def test_given_duplicate_json_key_when_validated_then_rejects_ambiguous_manifest(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
    ) -> None:
        # given
        text = artifact.manifest_path.read_text()
        artifact.manifest_path.write_text(text[:-1] + ', "schema": 1}')
        # when
        with pytest.raises(ValueError, match="duplicate"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("name", ["objects/Aura", "profile.profdata"])
    def test_given_empty_coverage_payload_when_validated_then_rejects_artifact(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        name: str,
    ) -> None:
        # given
        (artifact.directory / name).write_bytes(b"")
        artifact.save()
        # when
        with pytest.raises(ValueError, match="empty"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    def test_given_incomplete_collection_when_manifest_written_then_preserves_previous_manifest(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
    ) -> None:
        # given
        from coverage_artifacts import write_manifest

        previous = artifact.manifest_path.read_bytes()
        (artifact.directory / "completed-tests.json").write_text("[]")
        # when
        with pytest.raises(ValueError, match="test inventory"):
            write_manifest(artifact.directory, artifact.identity, "package")
        # then
        assert artifact.manifest_path.read_bytes() == previous

    @pytest.mark.parametrize("complete", [False, 1, "true", None])
    def test_given_incomplete_collection_when_validated_then_rejects_artifact(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        complete: JsonValue,
    ) -> None:
        # given
        artifact.save({"complete": complete})
        # when
        with pytest.raises(ValueError, match="complete"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("inventory", [[], ["Suite/test", "Suite/test"], [""], [1], {}, None, ["Suite/missing"]])
    def test_given_incomplete_test_execution_when_validated_then_rejects_test_inventory(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        inventory: JsonValue,
    ) -> None:
        # given
        (artifact.directory / "completed-tests.json").write_text(json.dumps(inventory))
        artifact.save()
        # when
        with pytest.raises(ValueError, match="test inventory"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("value", ["", "  ", None, 1])
    def test_given_invalid_identity_field_when_constructed_then_rejects_identity(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        value: JsonValue,
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="identity"):
            CollectionIdentity(
                architecture=value,
                configuration=artifact.identity.configuration,
                revision=artifact.identity.revision,
                run=artifact.identity.run,
                source_digest=artifact.identity.source_digest,
                source_root=artifact.identity.source_root,
                toolchain=artifact.identity.toolchain,
            )
        # then

    @pytest.mark.parametrize("schema", [True, 2, 1.0, None, "1"])
    def test_given_invalid_schema_when_validated_then_rejects_artifact(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        schema: JsonValue,
    ) -> None:
        # given
        artifact.save({"schema": schema})
        # when
        with pytest.raises(ValueError, match="schema"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("inventory", [[], ["Suite/test", "Suite/test"], [""], ["  "], [1], {}, None])
    def test_given_invalid_test_plan_when_validated_then_rejects_test_inventory(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        inventory: JsonValue,
    ) -> None:
        # given
        (artifact.directory / "planned-tests.json").write_text(json.dumps(inventory))
        artifact.save()
        # when
        with pytest.raises(ValueError, match="test inventory"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("field", ["architecture", "configuration", "revision", "run", "source_digest", "source_root", "toolchain"])
    def test_given_mismatched_identity_when_validated_then_rejects_artifact(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        field: str,
    ) -> None:
        # given
        identity: dict[str, JsonValue] = asdict(artifact.identity)
        identity[field] = "different"
        artifact.save({"identity": identity})
        # when
        with pytest.raises(ValueError, match="identity"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("name", ["completed-tests.json", "objects/Aura", "planned-tests.json", "profile.profdata"])
    def test_given_missing_required_payload_when_validated_then_rejects_artifact(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        name: str,
    ) -> None:
        # given
        (artifact.directory / name).unlink()
        artifact.save()
        # when
        with pytest.raises(ValueError, match="missing required"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("name", ["build-stamp.json", "enumerated-tests.json", "native-events.jsonl", "source-inventory.json", "test-inventory.json", "test-summary.json", "tests.log"])
    def test_given_native_provenance_receipt_when_validated_then_preserves_hashed_receipt(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        name: str,
    ) -> None:
        # given
        (artifact.directory / name).write_bytes(b"native evidence")
        artifact.save()
        # when
        result = validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then
        assert result.profile == artifact.directory / "profile.profdata"

    @pytest.mark.parametrize("name", ["manifest.json", "objects", "objects/Aura", "profile.profdata"])
    def test_given_symlink_when_validated_then_rejects_artifact(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        name: str,
    ) -> None:
        # given
        path = artifact.directory / name
        destination = artifact.directory.parent / f"{artifact.directory.name}-link-target"
        path.rename(destination)
        path.symlink_to(destination, target_is_directory=destination.is_dir())
        # when
        with pytest.raises(ValueError, match="symlink"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    def test_given_undeclared_file_when_validated_then_rejects_inventory_mismatch(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
    ) -> None:
        # given
        (artifact.directory / "objects/other").write_bytes(b"extra mapping")
        # when
        with pytest.raises(ValueError, match="inventory"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    def test_given_unknown_file_entry_field_when_validated_then_rejects_inventory(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
    ) -> None:
        # given
        entries = artifact.manifest()["files"]
        assert isinstance(entries, list)
        assert isinstance(entries[0], dict)
        entries[0]["unexpected"] = True
        artifact.save({"files": entries})
        # when
        with pytest.raises(ValueError, match="file entry"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    def test_given_unknown_manifest_field_when_validated_then_rejects_schema(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
    ) -> None:
        # given
        artifact.save({"unexpected": True})
        # when
        with pytest.raises(ValueError, match="schema"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("name", ["extra.json", "objects", "manifest.json"])
    def test_given_unknown_or_directory_entry_when_validated_then_rejects_payload(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        name: str,
    ) -> None:
        # given
        if name == "extra.json":
            (artifact.directory / name).write_bytes(b"extra")
            artifact.save()
        else:
            entries = artifact.manifest()["files"]
            assert isinstance(entries, list)
            artifact.save({"files": entries + [{"path": name, "sha256": "0" * 64}]})
        # when
        with pytest.raises(ValueError, match="unknown|directory"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("name", ["../escape", "/escape", "objects/../profile.profdata", "objects//Aura", "./profile.profdata", "objects\\Aura", ""])
    def test_given_unsafe_file_path_when_validated_then_rejects_before_reading(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        name: str,
    ) -> None:
        # given
        artifact.save({"files": [{"path": name, "sha256": "0" * 64}]})
        # when
        with pytest.raises(ValueError, match="unsafe"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("kind", ["directory", "fifo"])
    def test_given_unsafe_filesystem_entry_when_validated_then_rejects_artifact(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        kind: str,
    ) -> None:
        # given
        path = artifact.directory / "unexpected"
        if kind == "directory":
            path.mkdir()
        else:
            os.mkfifo(path)
        # when
        with pytest.raises(ValueError, match="directory|regular"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then

    @pytest.mark.parametrize("suite", ["ios", "unknown", None, 1])
    def test_given_wrong_suite_when_validated_then_rejects_artifact(
        self: TestCoverageArtifacts,
        artifact: ArtifactScenario,
        suite: JsonValue,
    ) -> None:
        # given
        artifact.save({"suite": suite})
        # when
        with pytest.raises(ValueError, match="suite"):
            validate_artifact(artifact.manifest_path, artifact.identity, "package")
        # then
