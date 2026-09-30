#!/bin/zsh
# Builds BlackBarAI.app into ./build (release, ad-hoc signed) for the Mac you're on.
# For a universal .dmg to share, use ./scripts/package.sh instead.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/BlackBarAI.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/BlackBarAI "$APP/Contents/MacOS/BlackBarAI"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - --identifier app.blackbarai.BlackBarAI \
    --entitlements Resources/BlackBarAI.entitlements "$APP"
echo "Built $APP"
