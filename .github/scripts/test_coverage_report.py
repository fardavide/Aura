import html
import json
from pathlib import Path
import re

import pytest

import coverage_report

from coverage_report import Counter, Measurement, Scope, check_ratio, check_ratchets, measure_export


class TestCoverageReport:
    def test_given_failed_report_with_html_characters_when_rendered_then_shows_safe_exact_ratchets(
        self: TestCoverageReport,
        tmp_path: Path,
    ) -> None:
        # given
        filename = "AuraKit/Sources/A<&>.swift"
        toolchain = 'Xcode 26.1 <script>alert("x")</script>'
        baseline = {
            scope: Measurement(
                files=(filename,),
                lines=Counter(covered=8, count=10),
                regions=Counter(covered=8, count=10),
                scope=scope,
            )
            for scope in Scope
        }
        current = dict(baseline)
        current[Scope.PACKAGE] = Measurement(
            files=(filename,),
            lines=Counter(covered=8, count=10),
            regions=Counter(covered=7, count=10),
            scope=Scope.PACKAGE,
        )
        report = coverage_report.build_report(
            baseline=baseline,
            current=current,
            toolchain=toolchain,
        )
        output_path = tmp_path / "coverage.html"

        # when
        coverage_report.render_report(path=output_path, report=report)

        # then
        markup = output_path.read_text(encoding="utf-8")
        visible_text = html.unescape(re.sub(r"<[^>]*>", " ", markup))
        visible_text = re.sub(r"\s*/\s*", "/", visible_text)
        assert visible_text.count("FAILED") >= 2
        assert visible_text.count("PASSED") >= 5
        assert visible_text.count("8/10") >= 11
        assert "7/10" in visible_text
        for scope in Scope:
            assert visible_text.count(scope.value) >= 2
        assert visible_text.casefold().count("lines") >= 3
        assert visible_text.casefold().count("regions") >= 3
        assert html.escape(filename) in markup
        assert html.escape(toolchain) in markup
        assert filename not in markup
        assert toolchain not in markup

    def test_given_per_file_counters_when_reported_then_serializes_each_exact_counter(
        self: TestCoverageReport,
    ) -> None:
        # given
        file_counters = {
            "AuraKit/Sources/A.swift": coverage_report.FileCounters(
                lines=Counter(covered=2, count=3),
                regions=Counter(covered=1, count=2),
            ),
            "AuraKit/Sources/B.swift": coverage_report.FileCounters(
                lines=Counter(covered=3, count=5),
                regions=Counter(covered=2, count=3),
            ),
        }
        measurements = {
            scope: Measurement(
                file_counters=file_counters,
                files=tuple(file_counters),
                lines=Counter(covered=5, count=8),
                regions=Counter(covered=3, count=5),
                scope=scope,
            )
            for scope in Scope
        }

        # when
        report = coverage_report.build_report(
            baseline=measurements,
            current=measurements,
            toolchain="Xcode 26.1",
        )

        # then
        assert report["measurements"][Scope.PACKAGE.value]["file_counters"] == {
            "AuraKit/Sources/A.swift": {
                "lines": {"count": 3, "covered": 2},
                "regions": {"count": 2, "covered": 1},
            },
            "AuraKit/Sources/B.swift": {
                "lines": {"count": 5, "covered": 3},
                "regions": {"count": 3, "covered": 2},
            },
        }

    def test_given_files_with_distinct_counts_when_measured_then_preserves_each_file_counters(
        self: TestCoverageReport,
    ) -> None:
        # given
        export = {"data": [{"files": [
            {
                "filename": "/checkout/AuraKit/Sources/A.swift",
                "summary": {
                    "lines": {"count": 4, "covered": 3},
                    "regions": {"count": 2, "covered": 1},
                },
            },
            {
                "filename": "/checkout/AuraKit/Sources/B.swift",
                "summary": {
                    "lines": {"count": 6, "covered": 4},
                    "regions": {"count": 5, "covered": 3},
                },
            },
        ]}]}

        # when
        measured = measure_export(export=export, root="/checkout", scope=Scope.PACKAGE)

        # then
        assert measured.file_counters == {
            "AuraKit/Sources/A.swift": coverage_report.FileCounters(
                lines=Counter(covered=3, count=4),
                regions=Counter(covered=1, count=2),
            ),
            "AuraKit/Sources/B.swift": coverage_report.FileCounters(
                lines=Counter(covered=4, count=6),
                regions=Counter(covered=3, count=5),
            ),
        }

    def test_given_measurement_scope_disagrees_with_category_when_gated_then_rejects_the_scope(
        self: TestCoverageReport,
    ) -> None:
        # given
        current = {
            scope: Measurement(
                files=("AuraKit/Sources/A.swift",),
                lines=Counter(covered=8, count=10),
                regions=Counter(covered=8, count=10),
                scope=scope,
            )
            for scope in Scope
        }
        baseline = dict(current)
        baseline[Scope.PACKAGE] = Measurement(
            files=("AuraKit/Sources/A.swift",),
            lines=Counter(covered=8, count=10),
            regions=Counter(covered=8, count=10),
            scope=Scope("aura-production-ios-v1"),
        )

        # when
        with pytest.raises(ValueError, match="scope"):
            check_ratchets(baseline=baseline, current=current)
        # then

    def test_given_traversal_in_a_production_path_when_measured_then_rejects_the_source_path(
        self: TestCoverageReport,
    ) -> None:
        # given
        export = {"data": [{"files": [
            {
                "filename": "/checkout/Aura/App.swift",
                "summary": {
                    "lines": {"count": 5, "covered": 2},
                    "regions": {"count": 3, "covered": 1},
                },
            },
            {
                "filename": "/checkout/Aura/../../Dependency.swift",
                "summary": {
                    "lines": {"count": 100, "covered": 90},
                    "regions": {"count": 100, "covered": 90},
                },
            },
        ]}]}

        # when
        with pytest.raises(ValueError, match="source path"):
            measure_export(
                export=export,
                root="/checkout",
                scope=Scope("aura-production-ios-v1"),
            )
        # then

    def test_given_one_region_decrease_when_reported_then_serializes_the_failed_gate_and_all_ratchets(
        self: TestCoverageReport,
    ) -> None:
        # given
        baseline = {
            scope: Measurement(
                files=("AuraKit/Sources/A.swift",),
                lines=Counter(covered=8, count=10),
                regions=Counter(covered=8, count=10),
                scope=scope,
            )
            for scope in Scope
        }
        current = dict(baseline)
        current[Scope.PACKAGE] = Measurement(
            files=("AuraKit/Sources/A.swift",),
            lines=Counter(covered=8, count=10),
            regions=Counter(covered=7, count=10),
            scope=Scope.PACKAGE,
        )

        # when
        report = json.loads(json.dumps(coverage_report.build_report(
            baseline=baseline,
            current=current,
            toolchain="Xcode 26.1",
        )))

        # then
        assert report["passed"] is False
        assert report["schema"] == 1
        assert report["toolchain"] == "Xcode 26.1"
        assert report["measurements"] == {
            scope.value: {
                "files": list(measurement.files),
                "lines": {"count": measurement.lines.count, "covered": measurement.lines.covered},
                "regions": {"count": measurement.regions.count, "covered": measurement.regions.covered},
            }
            for scope, measurement in current.items()
        }
        assert len(report["ratchets"]) == 6
        assert {
            (ratchet["scope"], ratchet["metric"]): ratchet
            for ratchet in report["ratchets"]
        } == {
            (scope.value, metric): {
                "baseline": {"count": 10, "covered": 8},
                "current": {
                    "count": 10,
                    "covered": 7 if scope is Scope.PACKAGE and metric == "regions" else 8,
                },
                "metric": metric,
                "passed": not (scope is Scope.PACKAGE and metric == "regions"),
                "scope": scope.value,
            }
            for scope in Scope
            for metric in ("lines", "regions")
        }

    def test_given_complete_approved_baseline_when_loaded_then_preserves_all_measurements(
        self: TestCoverageReport,
        tmp_path: Path,
    ) -> None:
        # given
        fixtures = {
            "aura-production-ios-v1": (
                ("Aura/App.swift", "AuraKit/Sources/B.swift"),
                Counter(covered=16, count=20),
                Counter(covered=15, count=18),
            ),
            "aura-production-host-first-union-v1": (
                ("Aura/App.swift", "AuraKit/Sources/A.swift", "AuraKit/Sources/B.swift"),
                Counter(covered=24, count=30),
                Counter(covered=22, count=27),
            ),
            "aurakit-production-host-v1": (
                ("AuraKit/Sources/A.swift",),
                Counter(covered=8, count=10),
                Counter(covered=7, count=9),
            ),
        }
        expected = {
            Scope(scope_name): Measurement(
                files=files,
                lines=lines,
                regions=regions,
                scope=Scope(scope_name),
            )
            for scope_name, (files, lines, regions) in fixtures.items()
        }
        baseline_path = tmp_path / "baseline.json"
        baseline_path.write_text(
            json.dumps({
                "measurements": {
                    scope_name: {
                        "files": list(files),
                        "lines": {"count": lines.count, "covered": lines.covered},
                        "regions": {"count": regions.count, "covered": regions.covered},
                    }
                    for scope_name, (files, lines, regions) in fixtures.items()
                },
                "passed": True,
                "schema": 1,
                "toolchain": "Xcode 26.1",
            }),
            encoding="utf-8",
        )

        # when
        loaded = coverage_report.read_baseline(path=baseline_path, toolchain="Xcode 26.1")

        # then
        assert loaded == expected

    def test_given_baseline_from_another_toolchain_when_loaded_then_it_is_rejected(
        self: TestCoverageReport,
        tmp_path: Path,
    ) -> None:
        # given
        baseline_path = tmp_path / "baseline.json"
        baseline_path.write_text(
            json.dumps({
                "measurements": {
                    "aura-production-ios-v1": {
                        "files": ["Aura/App.swift", "AuraKit/Sources/B.swift"],
                        "lines": {"count": 20, "covered": 16},
                        "regions": {"count": 20, "covered": 16},
                    },
                    "aurakit-production-host-v1": {
                        "files": ["AuraKit/Sources/A.swift"],
                        "lines": {"count": 10, "covered": 8},
                        "regions": {"count": 10, "covered": 8},
                    },
                    "aura-production-host-first-union-v1": {
                        "files": [
                            "Aura/App.swift",
                            "AuraKit/Sources/A.swift",
                            "AuraKit/Sources/B.swift",
                        ],
                        "lines": {"count": 30, "covered": 24},
                        "regions": {"count": 30, "covered": 24},
                    },
                },
                "passed": True,
                "schema": 1,
                "toolchain": "Xcode 26.0",
            }),
            encoding="utf-8",
        )

        # when
        with pytest.raises(ValueError, match="toolchain"):
            coverage_report.read_baseline(path=baseline_path, toolchain="Xcode 26.1")
        # then

    def test_given_one_decreasing_region_when_gated_then_all_six_verdicts_are_retained(self) -> None:
        # given
        baseline = {
            scope: Measurement(files=("source.swift",), lines=Counter(8, 10), regions=Counter(8, 10), scope=scope)
            for scope in Scope
        }
        current = dict(baseline)
        current[Scope.PACKAGE] = Measurement(files=("source.swift",), lines=Counter(8, 10), regions=Counter(7, 10), scope=Scope.PACKAGE)

        # when
        verdicts = check_ratchets(baseline=baseline, current=current)

        # then
        assert len(verdicts) == 6
        assert verdicts.count(False) == 1

    def test_given_missing_category_when_gated_then_it_fails_instead_of_skipping(self) -> None:
        # given
        baseline = {}
        current = {}

        # when
        with pytest.raises(ValueError, match="all three"):
            check_ratchets(baseline=baseline, current=current)
        # then

    def test_given_a_decrease_hidden_by_rounding_when_compared_then_it_fails(self) -> None:
        # given
        baseline = Counter(covered=9999, count=10000)
        current = Counter(covered=9998, count=10000)

        # when
        passed = check_ratio(baseline=baseline, current=current)

        # then
        assert passed is False

    def test_given_dependency_paths_when_measured_then_only_production_roots_count(self) -> None:
        # given
        export = {"data": [{"files": [
            {"filename": "/checkout/AuraKit/Sources/Domain.swift", "summary": {"lines": {"covered": 3, "count": 4}, "regions": {"covered": 1, "count": 2}}},
            {"filename": "/checkout/Dependency/AuraKit/Sources/Fake.swift", "summary": {"lines": {"covered": 90, "count": 100}, "regions": {"covered": 90, "count": 100}}},
            {"filename": "/checkout/Aura/AppComposition.swift", "summary": {"lines": {"covered": 2, "count": 5}, "regions": {"covered": 1, "count": 3}}},
        ]}]}

        # when
        measured = measure_export(export=export, root="/checkout", scope=Scope.PACKAGE)

        # then
        assert measured.lines == Counter(covered=3, count=4)
        assert measured.regions == Counter(covered=1, count=2)

    @pytest.mark.parametrize("covered,count", [(0, 0), (-1, 5), (6, 5), (1, -1), (True, 2)])
    def test_given_invalid_counts_when_constructed_then_the_measurement_is_rejected(
        self,
        covered: int,
        count: int,
    ) -> None:
        # given
        # when
        with pytest.raises(ValueError, match="coverage counter"):
            Counter(covered=covered, count=count)
        # then
