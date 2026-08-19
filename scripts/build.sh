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
resources="$bundle/Contents/Resources"
mlx_license="$project_root/.build/xcode/SourcePackages/checkouts/mlx-swift-lm/LICENSE"
transformers_license="$project_root/.build/xcode/SourcePackages/checkouts/swift-transformers/LICENSE"

test -f "$mlx_license"
test -f "$transformers_license"
mkdir -p "$resources"
install -m 0644 "$project_root/LICENSE" "$resources/Adaptive-Dictation-GPL-3.0.txt"
install -m 0644 "$project_root/THIRD_PARTY_NOTICES.md" "$resources/THIRD_PARTY_NOTICES.md"
install -m 0644 "$mlx_license" "$resources/MLXSwiftLM-MIT.txt"
install -m 0644 "$transformers_license" "$resources/SwiftTransformers-Apache-2.0.txt"
codesign --force --deep --sign - "$bundle"
echo "$bundle"
