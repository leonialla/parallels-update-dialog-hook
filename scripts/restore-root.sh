#!/bin/zsh
set -euo pipefail

stage_dir=${0:A:h}
app=${1:?Parallels Desktop.app path required}
app_bin="$app/Contents/MacOS/prl_client_app"
app_hook="$app/Contents/Frameworks/libParallelsUpdateBlock.dylib"
app_resources="$app/Contents/_CodeSignature/CodeResources"
load_path='@executable_path/../Frameworks/libParallelsUpdateBlock.dylib'
original_hash='b3e7badd0e692149c5c0995385e0443747ef0bd1cf60e86864ef73c513127e7b'

[[ -f "$app_bin" && -f "$app_resources" ]] || { print -u2 'Parallels app not found'; exit 1; }
current_hash=$(shasum -a 256 "$app_bin" | awk '{print $1}')
[[ $(shasum -a 256 "$stage_dir/prl_client_app.original" | awk '{print $1}') == "$original_hash" ]] || {
  print -u2 'Local original executable does not match the expected build.'
  exit 1
}
if [[ "$current_hash" == "$original_hash" ]]; then
  print 'The original binary is already installed.'
  exit 0
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ "$version" == '26.2.2' && "$build" == '57373' ]] || { print -u2 'App version changed; refusing to restore over it.'; exit 1; }
otool -L "$app_bin" | grep -Fq "$load_path" || { print -u2 'Our load command is missing.'; exit 1; }
cmp -s "$stage_dir/libParallelsUpdateBlock.dylib" "$app_hook" || { print -u2 'Hook library changed; refusing to remove it.'; exit 1; }

if (( EUID == 0 )); then
  install -o root -g wheel -m 755 "$stage_dir/prl_client_app.original" "$app_bin.codex-restore"
  install -o root -g wheel -m 644 "$stage_dir/CodeResources.original" "$app_resources.codex-restore"
else
  install -m 755 "$stage_dir/prl_client_app.original" "$app_bin.codex-restore"
  install -m 644 "$stage_dir/CodeResources.original" "$app_resources.codex-restore"
fi
mv -f "$app_bin.codex-restore" "$app_bin"
mv -f "$app_resources.codex-restore" "$app_resources"
rm "$app_hook"

[[ $(shasum -a 256 "$app_bin" | awk '{print $1}') == "$original_hash" ]]
cmp -s "$stage_dir/CodeResources.original" "$app_resources"
print "Restored original files: $app"
