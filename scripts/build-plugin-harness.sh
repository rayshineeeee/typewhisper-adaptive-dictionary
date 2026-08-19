#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
app_frameworks="/Applications/TypeWhisper.app/Contents/Frameworks"
output_dir="$project_root/.build/plugin-harness"
executable="$output_dir/AdaptiveDictationPluginHarness"
bundle="$project_root/.build/xcode/Build/Products/Release/AdaptiveDictionaryPlugin.bundle"

"$project_root/scripts/prepare-sdk.sh"
mkdir -p "$output_dir"
xcrun swiftc \
    -parse-as-library \
    -target arm64-apple-macos14.0 \
    -I "$project_root/.build/sdk" \
    -F "$app_frameworks" \
    -framework TypeWhisperPluginSDK \
    -Xlinker -rpath \
    -Xlinker "$app_frameworks" \
    "$project_root/Tools/PluginHarness/main.swift" \
    -o "$executable"

ditto "$bundle" "$output_dir/AdaptiveDictionaryPlugin.bundle"
echo "$executable"
