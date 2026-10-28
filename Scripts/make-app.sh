#!/bin/sh
# Construit « PBIP Reader.app » à partir de la cible SwiftPM pbip-reader-app (non signée).
# Usage : Scripts/make-app.sh [dossier de sortie, par défaut .build]
set -eu
cd "$(dirname "$0")/.."
OUT="${1:-.build}"
swift build -c release --product pbip-reader-app
APP="$OUT/PBIP Reader.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/pbip-reader-app "$APP/Contents/MacOS/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>pbip-reader-app</string>
<key>CFBundleIdentifier</key><string>io.github.florentinodsn.pbip-reader</string>
<key>CFBundleName</key><string>PBIP Reader</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
echo "$APP"
