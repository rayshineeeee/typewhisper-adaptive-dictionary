#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
typewhisper_app="${TYPEWHISPER_APP_PATH:-/Applications/TypeWhisper.app}"
info_plist="$typewhisper_app/Contents/Info.plist"

if [[ ! -f "$info_plist" ]]; then
    echo "TypeWhisper is required at $typewhisper_app" >&2
    exit 1
fi

app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")"
sdk_tag="v$app_version"
source_dir="$project_root/.build/sdk-source"
module_dir="$project_root/.build/sdk/TypeWhisperPluginSDK.swiftmodule"

mkdir -p "$project_root/.build" "$module_dir"

if [[ ! -d "$source_dir/.git" ]]; then
    git clone --depth 1 --branch "$sdk_tag" \
        https://github.com/TypeWhisper/typewhisper-mac.git "$source_dir"
else
    git -C "$source_dir" fetch --depth 1 origin "refs/tags/$sdk_tag:refs/tags/$sdk_tag"
    git -C "$source_dir" checkout --detach --quiet "$sdk_tag"
fi

sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc \
    -parse-as-library \
    -module-name TypeWhisperPluginSDK \
    -target arm64-apple-macos14.0 \
    -sdk "$sdk_path" \
    -suppress-warnings \
    -emit-module \
    -emit-module-path "$module_dir/arm64-apple-macos.swiftmodule" \
    "$source_dir"/TypeWhisperPluginSDK/Sources/TypeWhisperPluginSDK/*.swift

echo "Prepared TypeWhisperPluginSDK module for TypeWhisper $app_version"
