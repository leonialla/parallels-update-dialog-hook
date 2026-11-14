#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
app=${1:-'/Applications/Parallels Desktop.app'}
[[ -f "$app/Contents/MacOS/prl_client_app" ]] || { print -u2 'Parallels app not found'; exit 1; }

if [[ "$app" == '/Applications/Parallels Desktop.app' ]] && pgrep -x prl_client_app >/dev/null; then
  print -u2 'Quit Parallels Desktop before patching it.'
  exit 1
fi

if [[ ! -f "$repo_dir/prebuilt/prl_client_app.patched" || ! -f "$repo_dir/prebuilt/libParallelsUpdateBlock.dylib" || ! -f "$repo_dir/prebuilt/entitlements.original.plist" || ! -f "$repo_dir/prebuilt/CodeResources.original" ]] ||
   { [[ $(shasum -a 256 "$app/Contents/MacOS/prl_client_app" | awk '{print $1}') == 'b3e7badd0e692149c5c0995385e0443747ef0bd1cf60e86864ef73c513127e7b' ]] && ! cmp -s "$repo_dir/prebuilt/CodeResources.original" "$app/Contents/_CodeSignature/CodeResources"; }; then
  "$repo_dir/scripts/build-prebuilt.command" "$app"
fi

stage_dir=$(mktemp -d /private/tmp/parallels-update-hook.XXXXXX)
trap 'rm -r "$stage_dir"' EXIT
cp "$repo_dir/scripts/install-root.sh" "$stage_dir/"
cp "$repo_dir/prebuilt/prl_client_app.original" "$stage_dir/"
cp "$repo_dir/prebuilt/CodeResources.original" "$stage_dir/"
cp "$repo_dir/prebuilt/prl_client_app.patched" "$stage_dir/"
cp "$repo_dir/prebuilt/libParallelsUpdateBlock.dylib" "$stage_dir/"
cp "$repo_dir/prebuilt/entitlements.original.plist" "$stage_dir/"
chmod +x "$stage_dir/install-root.sh"

if [[ -w "$app/Contents/MacOS" && -w "$app/Contents/Frameworks" ]]; then
  "$stage_dir/install-root.sh" "$app"
else
  sudo "$stage_dir/install-root.sh" "$app"
fi
