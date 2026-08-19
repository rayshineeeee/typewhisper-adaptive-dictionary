#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$project_root/.build/release}"
archive="$output_dir/AdaptiveDictionaryPlugin.zip"
checksum="$archive.sha256"

"$project_root/scripts/verify.sh"
bundle="$project_root/.build/xcode/Build/Products/Release/AdaptiveDictionaryPlugin.bundle"

mkdir -p "$output_dir"
if [[ -e "$archive" ]]; then
    unlink "$archive"
fi
if [[ -e "$checksum" ]]; then
    unlink "$checksum"
fi

ditto -c -k --sequesterRsrc --keepParent "$bundle" "$archive"

verification_dir="$(mktemp -d)"
cleanup() {
    rm -rf "$verification_dir"
}
trap cleanup EXIT

ditto -x -k "$archive" "$verification_dir"
packaged_bundle="$verification_dir/AdaptiveDictionaryPlugin.bundle"
test -d "$packaged_bundle"
codesign --verify --deep --strict "$packaged_bundle"
plutil -lint "$packaged_bundle/Contents/Info.plist"
plutil -convert xml1 -o /dev/null "$packaged_bundle/Contents/Resources/manifest.json"

(
    cd "$output_dir"
    shasum -a 256 "$(basename "$archive")" > "$(basename "$checksum")"
)

echo "$archive"
echo "$checksum"
