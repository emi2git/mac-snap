#!/bin/zsh
# Build "Emi Snap.app" and install it to ~/Applications
set -e
cd "$(dirname "$0")"
APP="build/Emi Snap.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
[[ -f Resources/AppIcon.icns ]] || ~/git/scripts/make-app-icon.sh "🪟" 52 120 246 Resources/AppIcon.icns
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
swiftc -O -parse-as-library Sources/main.swift -o "$APP/Contents/MacOS/EmiSnap"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Emi Snap</string>
<key>CFBundleDisplayName</key><string>Emi Snap</string>
<key>CFBundleIdentifier</key><string>com.emi2git.emisnap</string>
<key>CFBundleExecutable</key><string>EmiSnap</string>
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
pkill -x EmiSnap || true
rm -rf "$HOME/Applications/Emi Snap.app" && cp -R "$APP" ~/Applications/
open "$HOME/Applications/Emi Snap.app"
echo "Built → ~/Applications/Emi Snap.app"
