#!/bin/bash
set -euo pipefail

runtimes="$(xcrun simctl list runtimes --json)"
if ! jq -e '[.runtimes[] | select(
  .identifier == "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
  and .version == "27.0"
  and .buildversion == "24A434"
  and .isAvailable == true
)] | length == 1' <<< "$runtimes" > /dev/null; then
  echo "::error::Required iOS 27.0 build 24A434 runtime is not available."
  exit 1
fi

jq -c '.runtimes[] | {identifier, version, buildversion, isAvailable}' <<< "$runtimes"
simulator_id="$(xcrun simctl create Aura-Snapshots \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17 \
  com.apple.CoreSimulator.SimRuntime.iOS-27-0)"
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b
printf 'simulator_id=%s\n' "$simulator_id" >> "$GITHUB_OUTPUT"
