#!/bin/zsh
# Builds a downloadable BlackBarAI: universal (Apple Silicon + Intel) app,
# packaged as dist/BlackBarAI-<version>.dmg (drag to Applications) and .zip.
#
# With a "Developer ID Application" certificate in the keychain and a notary
# profile saved as "BlackBarAI" (xcrun notarytool store-credentials BlackBarAI …),
# the app and DMG are signed, notarized by Apple and stapled: they open with a
# plain double-click on any Mac. Without them, it falls back to an ad-hoc build
# that users approve once via Privacy & Security → Open Anyway.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
PROFILE=${NOTARY_PROFILE:-BlackBarAI}
DIST=dist
STAGE=$DIST/stage
APP=$STAGE/BlackBarAI.app
DMG=$DIST/BlackBarAI-$VERSION.dmg
ZIP=$DIST/BlackBarAI-$VERSION.zip

IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
if [[ -n "$IDENTITY" ]] && xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
    MODE=notarized
    echo "→ Signing as: $IDENTITY (will notarize with profile '$PROFILE')"
else
    MODE=adhoc
    [[ -n "$IDENTITY" ]] && echo "! Found $IDENTITY but no notary profile '$PROFILE'; building ad-hoc."
    echo "→ No Developer ID + notary profile: building ad-hoc (users click Open Anyway once)"
fi

echo "→ Building universal release $VERSION"
swift build -c release --arch arm64 --arch x86_64 >/dev/null

echo "→ Assembling app bundle"
rm -rf "$DIST"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/apple/Products/Release/BlackBarAI "$APP/Contents/MacOS/BlackBarAI"
# Drop debug info (it records local build paths such as your home folder).
strip -S -x "$APP/Contents/MacOS/BlackBarAI"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
xattr -cr "$APP"

if [[ $MODE == notarized ]]; then
    codesign --force --timestamp --options runtime \
        --entitlements Resources/BlackBarAI.entitlements \
        --sign "$IDENTITY" "$APP"
else
    codesign --force --sign - --identifier app.blackbarai.BlackBarAI \
        --entitlements Resources/BlackBarAI.entitlements "$APP"
fi
codesign --verify --deep --strict "$APP"

if [[ $MODE == notarized ]]; then
    echo "→ Notarizing app (Apple usually takes 1–5 minutes)"
    ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
    xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$PROFILE" --wait
    rm "$DIST/notarize.zip"
    xcrun stapler staple "$APP"
fi

echo "→ Creating DMG"
cp "scripts/How to open BlackBar.txt" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "BlackBar" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"

if [[ $MODE == notarized ]]; then
    codesign --force --timestamp --sign "$IDENTITY" "$DMG"
    echo "→ Notarizing DMG"
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
    spctl --assess --type exec -v "$APP"
fi

echo "→ Creating ZIP"
( cd "$STAGE" && ditto -c -k --keepParent BlackBarAI.app "../$(basename "$ZIP")" )

rm -rf "$STAGE"
echo "✓ $MODE build:"
ls -lh "$DIST"
