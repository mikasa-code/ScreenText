#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h}"
build_dir="$project_dir/build"
app_dir="$build_dir/ScreenText.app"
mkdir -p "$build_dir"

work_dir="$(mktemp -d "$build_dir/.build.XXXXXX")"
trap 'rm -rf -- "$work_dir"' EXIT
bundle_dir="$work_dir/ScreenText.app"
iconset="$work_dir/AppIcon.iconset"
mkdir -p "$bundle_dir/Contents/MacOS" "$bundle_dir/Contents/Resources" "$iconset"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$project_dir/Resources/AppIcon.png" \
        --out "$iconset/icon_${size}x${size}.png" >/dev/null
    pixels=$((size * 2))
    sips -z "$pixels" "$pixels" "$project_dir/Resources/AppIcon.png" \
        --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$bundle_dir/Contents/Resources/AppIcon.icns"

xcrun swiftc -swift-version 6 -O -whole-module-optimization \
    -target "$(uname -m)-apple-macosx15.0" \
    -framework AppKit -framework Carbon -framework Vision \
    "$project_dir"/Sources/*.swift -o "$bundle_dir/Contents/MacOS/ScreenText"
cp "$project_dir/Resources/Info.plist" "$bundle_dir/Contents/Info.plist"
cp "$project_dir/LICENSE" "$bundle_dir/Contents/Resources/LICENSE"
codesign --force --sign - "$bundle_dir"
codesign --verify --strict "$bundle_dir"

rm -rf -- "$app_dir"
mv -- "$bundle_dir" "$app_dir"
print "已生成：$app_dir"
