#!/bin/sh
# Construit « PBIP Reader.app » à partir de la cible SwiftPM pbip-reader-app.
# Usage : Scripts/make-app.sh [dossier de sortie, par défaut .build]
# Variables facultatives :
#   UNIVERSAL=1      binaire universel Apple Silicon + Intel (sinon : architecture de la machine)
#   SIGN_IDENTITY    identité Developer ID ; l'app est alors signée (runtime renforcé, horodatage)
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-.build}"
VERSION=$(sed -n 's/.*current = "\(.*\)".*/\1/p' Sources/PBIPKit/PBIPKit.swift)

if [ "${UNIVERSAL:-0}" = 1 ]; then
  swift build -c release --product pbip-reader-app --arch arm64 --arch x86_64
  BINARY=.build/apple/Products/Release/pbip-reader-app
else
  swift build -c release --product pbip-reader-app
  BINARY=.build/release/pbip-reader-app
fi

APP="$OUT/PBIP Reader.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/"

# Icône : dessinée par Scripts/make-icon.swift, déclinée en .icns avec sips et iconutil.
ICONSET=".build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
swift Scripts/make-icon.swift .build/AppIcon-1024.png
for SIZE in 16 32 128 256 512; do
  sips -z $SIZE $SIZE .build/AppIcon-1024.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z $DOUBLE $DOUBLE .build/AppIcon-1024.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>pbip-reader-app</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>io.github.florentinodsn.pbip-reader</string>
<key>CFBundleName</key><string>PBIP Reader</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
fi
echo "$APP"
