from __future__ import annotations

from pathlib import Path
import re
import subprocess

import pytest

import coverage_products
from coverage_inventory import decode_json


class TestApplicationReference:
    def test_given_export_ignore_hides_committed_test_missing_from_worktree_when_reference_is_verified_then_incomplete_source_proof_is_rejected(
        self: TestApplicationReference,
        tmp_path: Path,
    ) -> None:
        # given
        scenario = self.Scenario(tmp_path)
        subprocess.run(
            ("git", "cat-file", "-e", f"{scenario.reference_revision}:AuraTests/SnapshotTests.swift"),
            capture_output=True,
            check=True,
            cwd=scenario.root,
        )
        (scenario.root / ".git/info/attributes").write_text("AuraTests/SnapshotTests.swift export-ignore\n")
        snapshot_tests = scenario.root / "AuraTests/SnapshotTests.swift"
        snapshot_tests.unlink()

        # when
        with pytest.raises(ValueError, match="inventory|protected|SnapshotTests"):
            coverage_products.verify_application_reference(
                root=scenario.root,
                revision=scenario.reference_revision,
            )

        # then
        assert not snapshot_tests.exists()

    def test_given_committed_snapshot_assertion_change_hidden_by_worktree_restore_when_reference_is_verified_then_collection_commit_is_rejected(
        self: TestApplicationReference,
        tmp_path: Path,
    ) -> None:
        # given
        scenario = self.Scenario(tmp_path)
        snapshot_tests = scenario.root / "AuraTests/SnapshotTests.swift"
        unchanged_assertions = snapshot_tests.read_text()
        snapshot_tests.write_text("changed committed screenshot tolerance\n")
        scheme = scenario.root / "Aura.xcodeproj/xcshareddata/xcschemes/Aura.xcscheme"
        serial_scheme = scheme.read_text()
        scheme.write_text(serial_scheme.replace('parallelizable="NO"', 'parallelizable="YES"'))
        git = (
            "git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
            "-c", "user.email=coverage-proof@example.invalid", "-c", "user.name=CoverageProof",
        )
        for arguments in (
            ("add", "AuraTests/SnapshotTests.swift", "Aura.xcodeproj/xcshareddata/xcschemes/Aura.xcscheme"),
            ("commit", "-m", "Changed committed screenshot assertion"),
        ):
            subprocess.run((*git, *arguments), capture_output=True, check=True, cwd=scenario.root, text=True)
        snapshot_tests.write_text(unchanged_assertions)
        scheme.write_text(serial_scheme)

        # when
        with pytest.raises(ValueError, match=r"SnapshotTests\.swift"):
            coverage_products.verify_application_reference(
                root=scenario.root,
                revision=scenario.reference_revision,
            )

        # then
        assert snapshot_tests.read_text() == unchanged_assertions
        assert 'parallelizable="NO"' in scheme.read_text()

    def test_given_only_approved_instrumentation_changes_when_reference_is_verified_then_proof_retains_distinct_collection_and_main_revisions(
        self: TestApplicationReference,
        tmp_path: Path,
    ) -> None:
        # given
        scenario = self.Scenario(tmp_path)

        # when
        proof = coverage_products.verify_application_reference(
            root=scenario.root,
            revision=scenario.reference_revision,
        )

        # then
        assert proof.collection_revision == scenario.collection_revision
        assert proof.revision == scenario.reference_revision
        assert proof.collection_revision != proof.revision
        assert proof.verified_files == scenario.protected_files
        assert re.fullmatch(r"[0-9a-f]{64}", proof.source_digest)

    def test_given_reference_scheme_without_parallelizable_attribute_when_serial_candidate_is_verified_then_default_parallelization_is_normalized(
        self: TestApplicationReference,
        tmp_path: Path,
    ) -> None:
        # given
        scenario = self.Scenario(
            root=tmp_path,
            reference_uses_default_parallelization=True,
        )

        # when
        proof = coverage_products.verify_application_reference(
            root=scenario.root,
            revision=scenario.reference_revision,
        )

        # then
        assert proof.collection_revision == scenario.collection_revision
        assert proof.revision == scenario.reference_revision
        assert proof.verified_files == scenario.protected_files

    def test_given_shallow_checkout_missing_frozen_reference_when_cli_fetches_reference_then_proof_preserves_collection_commit_and_checkout(
        self: TestApplicationReference,
        capsys: pytest.CaptureFixture[str],
        tmp_path: Path,
    ) -> None:
        # given
        scenario = self.Scenario(tmp_path / "remote")
        (scenario.root / ".ai/plan/coverage-review.md").write_text("follow-up coverage review\n")
        git = (
            "git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
            "-c", "user.email=coverage-proof@example.invalid", "-c", "user.name=CoverageProof",
        )
        for arguments in (
            ("add", ".ai/plan/coverage-review.md"),
            ("commit", "-m", "Follow-up instrumentation review"),
        ):
            subprocess.run((*git, *arguments), capture_output=True, check=True, cwd=scenario.root, text=True)
        collection_revision = subprocess.run(
            ("git", "rev-parse", "HEAD"), capture_output=True, check=True, cwd=scenario.root, text=True,
        ).stdout.strip()
        shallow_root = tmp_path / "shallow"
        subprocess.run(
            ("git", "-c", "core.hooksPath=/dev/null", "clone", "--depth", "2", scenario.root.as_uri(), str(shallow_root)),
            capture_output=True,
            check=True,
            text=True,
        )
        missing_reference = subprocess.run(
            ("git", "cat-file", "-e", f"{scenario.reference_revision}^{{commit}}"),
            capture_output=True,
            cwd=shallow_root,
        )
        assert missing_reference.returncode != 0
        original_refs = subprocess.run(
            ("git", "show-ref"), capture_output=True, check=True, cwd=shallow_root,
        ).stdout
        original_status = subprocess.run(
            ("git", "status", "--porcelain=v1", "-z", "--untracked-files=all"),
            capture_output=True,
            check=True,
            cwd=shallow_root,
        ).stdout

        # when
        exit_code = coverage_products.main(
            ("verify-reference", "--revision", scenario.reference_revision, "--fetch-missing"),
            root=shallow_root,
        )

        # then
        assert exit_code == 0
        proof = decode_json(capsys.readouterr().out)
        assert isinstance(proof, dict)
        assert proof.get("schema") == 1
        assert proof.get("collection_revision") == collection_revision
        assert proof.get("revision") == scenario.reference_revision
        assert proof.get("collection_revision") != proof.get("revision")
        assert proof.get("verified_files") == list(scenario.protected_files)
        subprocess.run(
            ("git", "cat-file", "-e", f"{scenario.reference_revision}^{{commit}}"),
            capture_output=True,
            check=True,
            cwd=shallow_root,
        )
        assert subprocess.run(
            ("git", "rev-parse", "HEAD"), capture_output=True, check=True, cwd=shallow_root, text=True,
        ).stdout.strip() == collection_revision
        assert subprocess.run(
            ("git", "show-ref"), capture_output=True, check=True, cwd=shallow_root,
        ).stdout == original_refs
        assert subprocess.run(
            ("git", "status", "--porcelain=v1", "-z", "--untracked-files=all"),
            capture_output=True,
            check=True,
            cwd=shallow_root,
        ).stdout == original_status

    def test_given_top_level_application_directory_symlink_when_reference_is_verified_then_outside_source_alias_is_rejected(
        self: TestApplicationReference,
        tmp_path: Path,
    ) -> None:
        # given
        scenario = self.Scenario(tmp_path / "repository")
        application_directory = scenario.root / "Aura"
        external_application = tmp_path / "external-application"
        application_directory.rename(external_application)
        application_directory.symlink_to(external_application, target_is_directory=True)

        # when
        with pytest.raises(ValueError, match="symlink"):
            coverage_products.verify_application_reference(
                root=scenario.root,
                revision=scenario.reference_revision,
            )

        # then
        assert (external_application / "App.swift").read_text() == "struct App {}\n"

    def test_given_tree_object_sha_when_reference_is_verified_then_noncommit_reference_is_rejected(
        self: TestApplicationReference,
        tmp_path: Path,
    ) -> None:
        # given
        scenario = self.Scenario(tmp_path)
        tree_revision = subprocess.run(
            ("git", "rev-parse", f"{scenario.reference_revision}^{{tree}}"),
            capture_output=True,
            check=True,
            cwd=scenario.root,
            text=True,
        ).stdout.strip()

        # when
        with pytest.raises(ValueError, match="commit"):
            coverage_products.verify_application_reference(
                root=scenario.root,
                revision=tree_revision,
            )

        # then
        assert tree_revision != scenario.reference_revision

    class Scenario:
        def __init__(
            self: TestApplicationReference.Scenario,
            root: Path,
            reference_uses_default_parallelization: bool = False,
        ) -> None:
            self.root = root
            scheme_parallelization = "" if reference_uses_default_parallelization else ' parallelizable="YES"'
            protected_inputs = {
                "Aura/App.swift": "struct App {}\n",
                "Aura.xcodeproj/project.pbxproj": "unchanged multiplatform target graph\n",
                "Aura.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved": '{"pins": []}\n',
                "Aura.xcodeproj/xcshareddata/xcschemes/Aura.xcscheme": f'<Scheme><TestAction buildConfiguration="Debug"><Testables><TestableReference{scheme_parallelization}/></Testables></TestAction></Scheme>\n',
                "AuraKit/.swiftpm/xcode/xcshareddata/xcschemes/AuraKitTests.xcscheme": '<Scheme><TestAction buildConfiguration="Debug"/></Scheme>\n',
                "AuraKit/Package.swift": "unchanged package target graph\n",
                "AuraKit/Sources/Feature.swift": "struct Feature {}\n",
                "AuraKit/Tests/FeatureTests.swift": "unchanged package tests\n",
                "AuraTests/Resources/fixture.json": '{"unchanged": true}\n',
                "AuraTests/SnapshotTests.swift": "unchanged screenshot assertions and tolerances\n",
                "AuraTests/__Snapshots__/screen.png": "unchanged screenshot bytes\n",
            }
            self.protected_files = tuple(sorted(protected_inputs))
            for name, content in protected_inputs.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            git = (
                "git", "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null",
                "-c", "init.defaultBranch=main", "-c", "user.email=coverage-proof@example.invalid",
                "-c", "user.name=CoverageProof",
            )
            for arguments in (
                ("init",),
                ("add", "."),
                ("commit", "-m", "Frozen application reference"),
            ):
                subprocess.run((*git, *arguments), capture_output=True, check=True, cwd=root, text=True)
            self.reference_revision = subprocess.run(
                (*git, "rev-parse", "HEAD"), capture_output=True, check=True, cwd=root, text=True,
            ).stdout.strip()
            instrumentation_changes = {
                ".ai/plan/coverage-execution.md": "coverage instrumentation documentation\n",
                ".github/scripts/coverage_collect.py": "coverage collection tooling\n",
                ".github/workflows/ci.yml": "instrumented required jobs\n",
                "Aura.xcodeproj/xcshareddata/xcschemes/Aura.xcscheme": protected_inputs[
                    "Aura.xcodeproj/xcshareddata/xcschemes/Aura.xcscheme"
                ].replace('parallelizable="YES"', 'parallelizable="NO"').replace(
                    '<TestableReference/>', '<TestableReference parallelizable="NO"/>',
                ),
                "Makefile": "coverage instrumentation targets\n",
            }
            for name, content in instrumentation_changes.items():
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content)
            for arguments in (
                ("add", "."),
                ("commit", "-m", "Published coverage instrumentation candidate"),
            ):
                subprocess.run((*git, *arguments), capture_output=True, check=True, cwd=root, text=True)
            self.collection_revision = subprocess.run(
                (*git, "rev-parse", "HEAD"), capture_output=True, check=True, cwd=root, text=True,
            ).stdout.strip()
