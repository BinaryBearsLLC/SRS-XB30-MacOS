#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP=build/XB30-Control.app
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Build both architectures against the macOS 13 API availability floor.
for arch in arm64 x86_64; do
 xcrun swiftc -O -whole-module-optimization -parse-as-library -target "$arch-apple-macos13.0" Sources/XB30Control.swift -o "build/XB30-Control-$arch" -framework SwiftUI -framework IOBluetooth -framework IOKit
done
lipo -create build/XB30-Control-arm64 build/XB30-Control-x86_64 -output "$APP/Contents/MacOS/XB30-Control"
cp Info.plist "$APP/Contents/Info.plist"
cp assets/BinaryBearsMark.png assets/AppIcon.png assets/AppIcon.icns assets/MenuBarTemplate.pdf assets/SpeakerPreview.png "$APP/Contents/Resources/"
if [[ -n "${MACOS_SIGN_IDENTITY:-}" ]]; then
 codesign --force --options runtime --timestamp --sign "$MACOS_SIGN_IDENTITY" "$APP"
else
 codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "App built: $APP (Universal, macOS 13+)"
