#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"

swift test
bundle="$($project_root/scripts/build.sh | tail -n 1)"
harness="$($project_root/scripts/build-plugin-harness.sh | tail -n 1)"
executable="$bundle/Contents/MacOS/AdaptiveDictionaryPlugin"
manifest="$bundle/Contents/Resources/manifest.json"
info_plist="$bundle/Contents/Info.plist"

test -x "$executable"
test -x "$harness"
test -f "$manifest"
plutil -convert xml1 -o /dev/null "$manifest"
plutil -lint "$info_plist"

plugin_id="$(plutil -extract id raw "$manifest")"
principal_class="$(plutil -extract principalClass raw "$manifest")"
info_principal_class="$(plutil -extract NSPrincipalClass raw "$info_plist")"

[[ "$plugin_id" == "com.raysun.typewhisper.adaptive-dictionary" ]]
[[ "$principal_class" == "AdaptiveDictionaryPlugin" ]]
[[ "$info_principal_class" == "AdaptiveDictionaryPlugin" ]]
[[ "$(plutil -extract name raw "$manifest")" == "Adaptive Dictation" ]]
[[ "$(plutil -extract version raw "$manifest")" == "1.1.0" ]]
file "$executable" | grep -q "Mach-O 64-bit bundle arm64"
file "$harness" | grep -q "Mach-O 64-bit executable arm64"
otool -L "$executable" | grep -q "@rpath/TypeWhisperPluginSDK.framework"
otool -L "$executable" | grep -q "/System/Library/Frameworks/Metal.framework"
test -d "$bundle/Contents/Resources/mlx-swift_Cmlx.bundle"
test -d "$bundle/Contents/Resources/swift-transformers_Hub.bundle"
codesign --verify --deep --strict "$bundle"

if rg -n "URLSession|PluginHTTPClient|NWConnection|dataTask\(|uploadTask\(" \
    Sources/AdaptiveDictionaryCore Sources/AdaptiveDictionaryPlugin; then
    echo "Direct networking or remote inference code is forbidden." >&2
    exit 1
fi

if rg -n "import (Hub|HuggingFace)" Sources/AdaptiveDictionaryPlugin \
    --glob '!LocalGemmaRuntime.swift'; then
    echo "Model-download dependencies must stay isolated to LocalGemmaRuntime.swift." >&2
    exit 1
fi

rg -q "import Hub" Sources/AdaptiveDictionaryPlugin/LocalGemmaRuntime.swift
rg -q "semanticModelSetupRequested" Sources/AdaptiveDictionaryPlugin/LocalGemmaRuntime.swift
rg -q "case \.recordingStarted" Sources/AdaptiveDictionaryPlugin/AdaptiveDictionaryPlugin.swift
rg -q "case \.recordingStopped" Sources/AdaptiveDictionaryPlugin/AdaptiveDictionaryPlugin.swift
rg -q "defaultIdleUnloadSeconds = 600" Sources/AdaptiveDictionaryPlugin/LocalGemmaRuntime.swift
rg -q "recordingInProgress" Sources/AdaptiveDictionaryPlugin/LocalGemmaRuntime.swift
rg -q "RecordingStartedPayload" Tools/PluginHarness/main.swift
rg -q "revision: 09deb8c4e9056fcd76b60718bb50325d1730572b" project.yml

if find "$bundle" -name '*.safetensors' -print -quit | grep -q .; then
    echo "Model weights must not be embedded in the plugin bundle." >&2
    exit 1
fi

echo "Verified core tests, metadata, MLX resources, arm64 linkage, signature, explicit-download boundary, and no bundled weights."
