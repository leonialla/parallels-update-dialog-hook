#!/bin/zsh
set -euo pipefail

stage_dir=${0:A:h}
app=${1:?Parallels Desktop.app path required}
app_bin="$app/Contents/MacOS/prl_client_app"
app_hook="$app/Contents/Frameworks/libParallelsUpdateBlock.dylib"
original_hash='b3e7badd0e692149c5c0995385e0443747ef0bd1cf60e86864ef73c513127e7b'
load_path='@executable_path/../Frameworks/libParallelsUpdateBlock.dylib'

[[ -d "$app" && -f "$app_bin" ]] || { print -u2 'Parallels app not found'; exit 1; }
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
[[ "$version" == '26.2.2' && "$build" == '57373' ]] || { print -u2 'Unexpected application version'; exit 1; }
current_hash=$(shasum -a 256 "$app_bin" | awk '{print $1}')
if [[ "$current_hash" != "$original_hash" ]]; then
  if otool -L "$app_bin" | grep -Fq "$load_path" && cmp -s "$stage_dir/libParallelsUpdateBlock.dylib" "$app_hook"; then
    print 'The hook is already installed in this app.'
    exit 0
  fi
  print -u2 'The app binary does not match the 26.2.2 build in this codebase.'
  exit 1
fi

cmp -s "$stage_dir/CodeResources.original" "$app/Contents/_CodeSignature/CodeResources" || {
  print -u2 'Application signature resources differ from the local backup; rebuild from this app.'
  exit 1
}

codesign --verify --strict "$stage_dir/prl_client_app.patched"
codesign --verify --strict "$stage_dir/libParallelsUpdateBlock.dylib"
[[ $(shasum -a 256 "$stage_dir/prl_client_app.original" | awk '{print $1}') == "$original_hash" ]] || {
  print -u2 'Local original executable does not match the expected build.'
  exit 1
}

cp -p "$app_bin" "$stage_dir/rollback.prl_client_app"
cp -p "$app/Contents/_CodeSignature/CodeResources" "$stage_dir/rollback.CodeResources"
changed=0
rollback() {
  if (( changed )); then
    cp -p "$stage_dir/rollback.prl_client_app" "$app_bin.codex-rollback" && mv -f "$app_bin.codex-rollback" "$app_bin"
    cp -p "$stage_dir/rollback.CodeResources" "$app/Contents/_CodeSignature/CodeResources.codex-rollback" && mv -f "$app/Contents/_CodeSignature/CodeResources.codex-rollback" "$app/Contents/_CodeSignature/CodeResources"
    rm -f "$app_hook"
    print -u2 'Patch failed; restored the previous application files.'
  fi
}
trap rollback EXIT

if (( EUID == 0 )); then
  install -o root -g wheel -m 755 "$stage_dir/libParallelsUpdateBlock.dylib" "$app_hook.codex-new"
  install -o root -g wheel -m 755 "$stage_dir/prl_client_app.patched" "$app_bin.codex-new"
else
  install -m 755 "$stage_dir/libParallelsUpdateBlock.dylib" "$app_hook.codex-new"
  install -m 755 "$stage_dir/prl_client_app.patched" "$app_bin.codex-new"
fi
changed=1
mv -f "$app_hook.codex-new" "$app_hook"
mv -f "$app_bin.codex-new" "$app_bin"

codesign --force --sign - --entitlements "$stage_dir/entitlements.original.plist" "$app"
codesign --verify --deep --strict "$app"
otool -L "$app_bin" | grep -Fq "$load_path"
changed=0
print "Patched and signed: $app"
