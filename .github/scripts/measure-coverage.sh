#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 "$ROOT/.github/scripts/coverage_aggregate.py" \
    --baseline "$ROOT/.coverage-baseline/report.json" \
    --context "$ROOT/build/coverage-context.json" \
    --inputs "$ROOT/build/coverage-inputs" \
    --output "$ROOT/build/coverage" "$@"
