#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
app=${1:-'/Applications/Parallels Desktop.app'}

if [[ "$app" == '/Applications/Parallels Desktop.app' ]] && pgrep -x prl_client_app >/dev/null; then
  print -u2 'Quit Parallels Desktop before restoring it.'
  exit 1
fi

stage_dir=$(mktemp -d /private/tmp/parallels-update-restore.XXXXXX)
trap 'rm -r "$stage_dir"' EXIT
cp "$repo_dir/scripts/restore-root.sh" "$stage_dir/"
cp "$repo_dir/prebuilt/prl_client_app.original" "$stage_dir/"
cp "$repo_dir/prebuilt/CodeResources.original" "$stage_dir/"
cp "$repo_dir/prebuilt/libParallelsUpdateBlock.dylib" "$stage_dir/"
chmod +x "$stage_dir/restore-root.sh"

if [[ -w "$app/Contents/MacOS" && -w "$app/Contents/Frameworks" ]]; then
  "$stage_dir/restore-root.sh" "$app"
else
  sudo "$stage_dir/restore-root.sh" "$app"
fi
