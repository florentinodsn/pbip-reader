#!/bin/sh
# Construit dist/PBIP-Reader.dmg : app universelle et raccourci vers Applications.
# Usage : Scripts/make-dmg.sh
# Variables facultatives (sans elles, le .dmg n'est ni signé ni notarisé : essais locaux seulement) :
#   SIGN_IDENTITY                                  identité « Developer ID Application: … »
#   NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER   clé d'API App Store Connect pour notarytool
set -eu
cd "$(dirname "$0")/.."
VERSION=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/PBIPKit/PBIPKit.swift)
STAGE=.build/dmg
DMG=dist/PBIP-Reader.dmg

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE" dist
UNIVERSAL=1 Scripts/make-app.sh "$STAGE" >/dev/null
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "PBIP Reader $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO "$DMG"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
if [ -n "${NOTARY_KEY_PATH:-}" ]; then
  xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi
echo "$DMG"
