#!/bin/zsh
# Build "Mac Snap.app" and install it to ~/Applications
set -e
cd "$(dirname "$0")"
APP="build/Mac Snap.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
[[ -f Resources/AppIcon.icns ]] || ~/git/scripts/make-app-icon.sh "🪟" 52 120 246 Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
swiftc -O -parse-as-library Sources/main.swift -o "$APP/Contents/MacOS/MacSnap"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Mac Snap</string>
<key>CFBundleDisplayName</key><string>Mac Snap</string>
<key>CFBundleIdentifier</key><string>com.emi2git.emisnap</string><!-- kept from the Emi Snap days: the Accessibility grant hangs off it -->
<key>CFBundleExecutable</key><string>MacSnap</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Stable identity so the Accessibility grant survives rebuilds
codesign --force -s "Apple Development: emi2git@gmail.com (76UQD6DDM8)" "$APP"
mkdir -p ~/Applications
pkill -x MacSnap || true
rm -rf "$HOME/Applications/Mac Snap.app" && cp -R "$APP" ~/Applications/
open "$HOME/Applications/Mac Snap.app"
echo "Built → ~/Applications/Mac Snap.app"
