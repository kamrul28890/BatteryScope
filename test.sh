#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"
swift test --disable-xctest --jobs 2 "$@"
