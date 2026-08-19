#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
executable="$($project_root/scripts/build-plugin-harness.sh | tail -n 1)"
DYLD_FRAMEWORK_PATH="/Applications/TypeWhisper.app/Contents/Frameworks" "$executable" "$@"
