#!/bin/bash
set -euo pipefail

applications_directory="${1:-/Applications}"
xcode="$applications_directory/Xcode_27.0.app"
if [[ ! -d "$xcode" ]]; then
  echo "::error::Required Xcode installation not found: $xcode"
  exit 1
fi

sudo xcode-select -s "$xcode"
version="$(xcodebuild -version)"
echo "$version"
if [[ "$version" != $'Xcode 27.0\nBuild version 27A266a' ]]; then
  echo "::error::Expected Xcode 27.0 build 27A266a; the selected installation does not match."
  exit 1
fi
