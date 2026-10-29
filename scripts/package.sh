#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
release_version="$(tr -d '\r\n' < VERSION)"
./build.sh
task_package="dist/InternetPulse-$release_version-macos-arm64.zip"
/usr/bin/ditto -c -k --keepParent dist/InternetPulse.app "$task_package"
cd dist
/usr/bin/shasum -a 256 "$(basename "$task_package")" > SHA256SUMS.txt
echo "Release assets: $task_root/$task_package and dist/SHA256SUMS.txt"
