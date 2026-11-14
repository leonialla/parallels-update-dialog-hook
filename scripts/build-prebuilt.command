#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
app=${1:-'/Applications/Parallels Desktop.app'}
binary="$app/Contents/MacOS/prl_client_app"
frameworks="$app/Contents/Frameworks"
resources="$app/Contents/_CodeSignature/CodeResources"
expected_hash='b3e7badd0e692149c5c0995385e0443747ef0bd1cf60e86864ef73c513127e7b'

[[ -f "$binary" && -f "$resources" && -d "$frameworks/QtWidgets.framework" && -d "$frameworks/QtCore.framework" ]] || {
  print -u2 'Expected Parallels app files and Qt 5 frameworks are missing.'
  exit 1
}
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")
hash=$(shasum -a 256 "$binary" | awk '{print $1}')
[[ "$version" == '26.2.2' && "$build" == '57373' && "$hash" == "$expected_hash" ]] || {
  print -u2 'Expected an unmodified Parallels Desktop 26.2.2 (57373) application.'
  exit 1
}
mkdir -p "$repo_dir/prebuilt"
cp "$binary" "$repo_dir/prebuilt/prl_client_app.original"
cp "$resources" "$repo_dir/prebuilt/CodeResources.original"
codesign -d --xml --entitlements "$repo_dir/prebuilt/entitlements.original.plist" "$app" 2>/dev/null
plutil -lint "$repo_dir/prebuilt/entitlements.original.plist" >/dev/null

clang++ -std=c++17 -arch arm64 -arch x86_64 -dynamiclib -O2 \
  -fno-exceptions -fno-rtti \
  -o "$repo_dir/prebuilt/libParallelsUpdateBlock.dylib" \
  "$repo_dir/src/block.cpp" \
  -F"$frameworks" -framework QtWidgets -framework QtCore \
  -Wl,-rpath,'@loader_path'
codesign --force --sign - "$repo_dir/prebuilt/libParallelsUpdateBlock.dylib"

python3 "$repo_dir/src/add_load_dylib.py" \
  "$repo_dir/prebuilt/prl_client_app.original" \
  "$repo_dir/prebuilt/prl_client_app.patched" \
  '@executable_path/../Frameworks/libParallelsUpdateBlock.dylib'
codesign --force --sign - "$repo_dir/prebuilt/prl_client_app.patched"

codesign --verify --strict "$repo_dir/prebuilt/libParallelsUpdateBlock.dylib"
codesign --verify --strict "$repo_dir/prebuilt/prl_client_app.patched"
architectures=$(lipo -archs "$repo_dir/prebuilt/libParallelsUpdateBlock.dylib")
[[ "$architectures" == *arm64* && "$architectures" == *x86_64* ]]
print 'Local build artifacts are ready in prebuilt/.'
