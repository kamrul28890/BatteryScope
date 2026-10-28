#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration" --jobs 2
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
app_path="$PWD/build/BatteryScope.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/BatteryScope" "$app_path/Contents/MacOS/BatteryScope"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp LICENSE "$app_path/Contents/Resources/LICENSE.txt"
codesign --force --sign - "$app_path"
printf 'Built: %s\n' "$app_path"
