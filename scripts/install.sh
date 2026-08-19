#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
bundle="$($project_root/scripts/build.sh | tail -n 1)"
plugins_dir="$HOME/Library/Application Support/TypeWhisper/Plugins"
backups_dir="$HOME/Library/Application Support/TypeWhisper/PluginBackups"
target_bundle="$plugins_dir/AdaptiveDictionaryPlugin.bundle"
backup_bundle=""

mkdir -p "$plugins_dir" "$backups_dir"

if pgrep -x TypeWhisper >/dev/null; then
    osascript -e 'tell application id "com.typewhisper.mac" to quit' >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -x TypeWhisper >/dev/null || break
        sleep 0.25
    done
    if pgrep -x TypeWhisper >/dev/null; then
        pkill -TERM -x TypeWhisper
    fi
fi

if [[ -e "$target_bundle" ]]; then
    backup_bundle="$backups_dir/AdaptiveDictionaryPlugin.bundle.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$target_bundle" "$backup_bundle"
fi

restore_backup() {
    if [[ -n "$backup_bundle" && -e "$backup_bundle" && ! -e "$target_bundle" ]]; then
        mv "$backup_bundle" "$target_bundle"
    fi
}
trap restore_backup ERR

ditto "$bundle" "$target_bundle"
codesign --force --deep --sign - "$target_bundle"
defaults write com.typewhisper.mac \
    "plugin.com.raysun.typewhisper.adaptive-dictionary.enabled" -bool true
trap - ERR

open -a TypeWhisper
for _ in {1..40}; do
    pgrep -x TypeWhisper >/dev/null && break
    sleep 0.25
done

if ! pgrep -x TypeWhisper >/dev/null; then
    echo "TypeWhisper did not restart." >&2
    exit 1
fi

codesign --verify --deep --strict "$target_bundle"
echo "Installed and enabled $target_bundle"
if [[ -n "$backup_bundle" ]]; then
    echo "Previous bundle backed up to $backup_bundle"
fi
