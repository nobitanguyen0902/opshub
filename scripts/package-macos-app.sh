#!/usr/bin/env bash

set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-${VERSION:-}}"

if [[ -z "$version" ]]; then
    version="$(git -C "$root_dir" describe --tags --always --dirty 2>/dev/null || echo "0.0.0")"
fi

build_dir="$root_dir/.build/release"
app_dir="$root_dir/dist/OpsHub.app"
archive_path="$root_dir/dist/OpsHub.zip"

rm -rf "$app_dir" "$archive_path"
swift build --package-path "$root_dir" --configuration release

mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Frameworks" "$app_dir/Contents/Resources"
cp "$build_dir/OpsHub" "$app_dir/Contents/MacOS/OpsHub"
ditto "$build_dir/Sparkle.framework" "$app_dir/Contents/Frameworks/Sparkle.framework"
cp "$root_dir/Packaging/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$app_dir/Contents/MacOS/OpsHub"
sed "s/@VERSION@/$version/g" "$root_dir/Packaging/Info.plist" > "$app_dir/Contents/Info.plist"

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app_dir/Contents/Frameworks/Sparkle.framework"
    codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY" "$app_dir"
else
    codesign --force --sign - "$app_dir/Contents/Frameworks/Sparkle.framework"
    codesign --force --sign - "$app_dir"
fi

mkdir -p "$(dirname "$archive_path")"
COPYFILE_DISABLE=1 ditto -c -k --keepParent --norsrc "$app_dir" "$archive_path"
shasum -a 256 "$archive_path"
