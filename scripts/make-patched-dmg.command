#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
original=${1:?Usage: make-patched-dmg.command /path/to/installer.dmg [output.dmg]}
output=${2:-"$repo_dir/dist/ParallelsDesktop_26_2_2_57373_UpdateHook.dmg"}
[[ -f "$original" ]] || { print -u2 'Input DMG not found'; exit 1; }
[[ ! -e "$output" ]] || { print -u2 'Output already exists; refusing to overwrite it'; exit 1; }

stage_dir=$(mktemp -d /private/tmp/parallels-update-dmg.XXXXXX)
mount_dir="$stage_dir/mount"
volume_dir="$stage_dir/volume"
mkdir -p "$mount_dir" "$volume_dir"
mounted=0
cleanup() {
  if (( mounted )); then
    hdiutil detach "$mount_dir" >/dev/null 2>&1 || true
  fi
  rm -rf "$stage_dir"
}
trap cleanup EXIT

hdiutil attach -readonly -nobrowse -mountpoint "$mount_dir" "$original"
mounted=1
[[ -d "$mount_dir/Parallels Desktop.app" && -d "$mount_dir/Install.app" ]] || {
  print -u2 'Expected application bundles are missing from the DMG.'
  exit 1
}
ditto "$mount_dir" "$volume_dir"
"$repo_dir/scripts/build-prebuilt.command" "$volume_dir/Parallels Desktop.app"
"$repo_dir/scripts/patch-installed.command" "$volume_dir/Parallels Desktop.app"
codesign --verify --deep --strict "$volume_dir/Parallels Desktop.app"
codesign --verify --deep --strict "$volume_dir/Install.app"

mkdir -p "${output:h}"
hdiutil create -srcfolder "$volume_dir" -volname 'Parallels Desktop 26.2.2 Update Hook' \
  -fs HFS+ -format UDZO "$output"
hdiutil verify "$output"
print "Patched DMG created: $output"
