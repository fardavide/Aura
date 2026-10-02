PYTHON ?= python3
CONTEXT ?= build/coverage-context.json
DERIVED ?= build/derived/ios
INPUTS ?= build/coverage-inputs
OUTPUT ?= build/coverage
BASELINE ?= .coverage-baseline/report.json
SHARD ?=
SIMULATOR ?=
IOS_SHARDS ?= 2

.PHONY: coverage coverage-baseline-fetch coverage-candidate coverage-context coverage-ios coverage-ios-build coverage-macos-build coverage-package coverage-products coverage-products-restore coverage-report coverage-tests

# Local collection uses the same required executions and aggregation gate as CI.
# Run sequentially on one Mac; CI gives each whole-suite shard its own runner.
coverage:
	$(MAKE) coverage-baseline-fetch
	$(PYTHON) .github/scripts/coverage_collect.py prepare-local
	$(MAKE) coverage-context
	$(MAKE) coverage-package
	$(MAKE) coverage-ios-build
	$(MAKE) coverage-ios SHARD=0
	$(MAKE) coverage-ios SHARD=1
	$(MAKE) coverage-macos-build
	$(MAKE) coverage-report

coverage-baseline-fetch:
	$(PYTHON) .github/scripts/coverage_baseline.py --output $(BASELINE)

coverage-candidate:
	$(PYTHON) .github/scripts/coverage_aggregate.py --candidate --context $(CONTEXT) --inputs $(INPUTS) --output $(OUTPUT) --ios-shards $(IOS_SHARDS)

coverage-context:
	$(PYTHON) .github/scripts/coverage_collect.py context --output $(CONTEXT)

coverage-ios:
	$(PYTHON) .github/scripts/coverage_collect.py ios --context $(CONTEXT) --derived $(DERIVED) --inputs $(INPUTS) $(if $(SHARD),--shard $(SHARD)) $(if $(SIMULATOR),--simulator $(SIMULATOR))

coverage-ios-build:
	$(PYTHON) .github/scripts/coverage_collect.py ios-build --context $(CONTEXT) --derived $(DERIVED)

coverage-macos-build:
	xcodebuild build -scheme Aura -destination 'generic/platform=macOS' -quiet CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -jobs 4

coverage-package:
	$(PYTHON) .github/scripts/coverage_collect.py package --context $(CONTEXT) --inputs $(INPUTS)

coverage-products:
	$(PYTHON) .github/scripts/coverage_collect.py products --context $(CONTEXT) --derived $(DERIVED)

coverage-products-restore:
	$(PYTHON) .github/scripts/coverage_collect.py restore-products --context $(CONTEXT) --derived $(DERIVED)

coverage-report:
	$(PYTHON) .github/scripts/coverage_aggregate.py --baseline $(BASELINE) --context $(CONTEXT) --inputs $(INPUTS) --output $(OUTPUT) --ios-shards $(IOS_SHARDS)

coverage-tests:
	$(PYTHON) -m pytest .github/scripts -m 'not native' -q
