#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
./build.sh
architecture="$(uname -m)"
mkdir -p dist
archive_name="BatteryScope-0.2.0-macOS-$architecture.zip"
archive="$PWD/dist/$archive_name"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent build/BatteryScope.app "$archive"
(cd dist && /usr/bin/shasum -a 256 "$archive_name" > "$archive_name.sha256")
printf 'Packaged: %s\n' "$archive"
