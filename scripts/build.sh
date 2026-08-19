#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
build_log="$project_root/.build/xcodebuild.log"

"$project_root/scripts/prepare-sdk.sh"
cd "$project_root"
xcodegen generate

if ! xcodebuild \
    -project AdaptiveDictionary.xcodeproj \
    -scheme AdaptiveDictionaryPlugin \
    -configuration Release \
    -derivedDataPath .build/xcode \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGNING_REQUIRED=NO \
    -skipPackagePluginValidation \
    ARCHS=arm64 \
    build > "$build_log" 2>&1; then
    tail -n 120 "$build_log" >&2
    exit 1
fi

bundle="$project_root/.build/xcode/Build/Products/Release/AdaptiveDictionaryPlugin.bundle"
codesign --force --deep --sign - "$bundle"
echo "$bundle"
