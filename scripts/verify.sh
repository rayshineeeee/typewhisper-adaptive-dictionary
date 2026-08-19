#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

swift test
bundle="$($project_root/scripts/build.sh | tail -n 1)"
executable="$bundle/Contents/MacOS/AdaptiveDictionaryPlugin"
manifest="$bundle/Contents/Resources/manifest.json"
info_plist="$bundle/Contents/Info.plist"

test -x "$executable"
test -f "$manifest"
plutil -convert xml1 -o /dev/null "$manifest"
plutil -lint "$info_plist"

plugin_id="$(plutil -extract id raw "$manifest")"
principal_class="$(plutil -extract principalClass raw "$manifest")"
info_principal_class="$(plutil -extract NSPrincipalClass raw "$info_plist")"

[[ "$plugin_id" == "com.raysun.typewhisper.adaptive-dictionary" ]]
[[ "$principal_class" == "AdaptiveDictionaryPlugin" ]]
[[ "$info_principal_class" == "AdaptiveDictionaryPlugin" ]]
file "$executable" | grep -q "Mach-O 64-bit bundle arm64"
otool -L "$executable" | grep -q "@rpath/TypeWhisperPluginSDK.framework"
codesign --verify --deep --strict "$bundle"

if rg -n "URLSession|PluginHTTPClient|NWConnection|Network\.framework|dataTask\(|uploadTask\(" \
    Sources/AdaptiveDictionaryCore Sources/AdaptiveDictionaryPlugin; then
    echo "Runtime networking code is forbidden." >&2
    exit 1
fi

echo "Verified 23 engine tests, bundle metadata, arm64 Mach-O type, SDK linkage, signature, and no runtime networking code."
