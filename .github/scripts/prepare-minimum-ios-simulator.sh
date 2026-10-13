#!/bin/bash
set -euo pipefail

runtimes="$(xcrun simctl list runtimes --json)"
if ! jq -e '[.runtimes[] | select(
  .identifier == "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
  and .version == "26.0" and .isAvailable == true
)] | length == 1' <<< "$runtimes" > /dev/null; then
  xcodebuild -downloadPlatform iOS -buildVersion 26.0 -architectureVariant arm64
  runtimes="$(xcrun simctl list runtimes --json)"
fi

if ! jq -e '[.runtimes[] | select(
  .identifier == "com.apple.CoreSimulator.SimRuntime.iOS-26-0"
  and .version == "26.0" and .isAvailable == true
)] | length == 1' <<< "$runtimes" > /dev/null; then
  echo "::error::Required iOS 26.0 runtime is not available after provisioning."
  exit 1
fi

jq -c '.runtimes[] | {identifier, version, buildversion, isAvailable}' <<< "$runtimes"
simulator_id="$(xcrun simctl create Aura-Minimum-iOS \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17 \
  com.apple.CoreSimulator.SimRuntime.iOS-26-0)"
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
printf 'simulator_id=%s\n' "$simulator_id" >> "$GITHUB_OUTPUT"
