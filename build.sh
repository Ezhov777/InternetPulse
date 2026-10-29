#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
cd "$task_root"
release_version="$(tr -d '\r\n' < VERSION)"
build_number="$(tr -d '\r\n' < BUILD_NUMBER)"
[[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid VERSION'; exit 1; }
[[ "$build_number" =~ ^[0-9]+$ ]] || { echo 'Invalid BUILD_NUMBER'; exit 1; }
task_app="${INTERNETPULSE_OUTPUT:-$task_root/dist/InternetPulse.app}"
mkdir -p build "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
task_sdk="$(xcrun --show-sdk-path)"
xcrun clang -O2 -Wall -Wextra -target arm64-apple-macosx14.0 -isysroot "$task_sdk" \
    "-DRP_VERSION=\"$release_version\"" -c Sources/NetworkEngine.c -o build/NetworkEngine.o
xcrun swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macosx14.0 \
    -sdk "$task_sdk" -import-objc-header Sources/NetworkEngine.h Sources/*.swift \
    build/NetworkEngine.o -lcurl -framework AppKit -framework SwiftUI \
    -o "$task_app/Contents/MacOS/InternetPulse"
cat > "$task_app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Internet Pulse</string>
<key>CFBundleDisplayName</key><string>Internet Pulse</string>
<key>CFBundleIdentifier</key><string>local.routerpulse.app</string>
<key>CFBundleExecutable</key><string>InternetPulse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$release_version</string>
<key>CFBundleVersion</key><string>$build_number</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 InternetPulse contributors</string>
</dict></plist>
PLIST
cp Assets/AppIcon.icns "$task_app/Contents/Resources/"
cp LICENSE "$task_app/Contents/Resources/LICENSE.txt"
cp Resources/Translations.json "$task_app/Contents/Resources/"
cp Resources/Servers.json "$task_app/Contents/Resources/"
cp Resources/ReleaseHistory.json "$task_app/Contents/Resources/"
/usr/bin/codesign --force --sign - "$task_app"
/usr/bin/codesign --verify --strict "$task_app"
echo "Built InternetPulse $release_version: $task_app"
