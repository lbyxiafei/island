#!/usr/bin/env bash
#
# Assembles a real .app bundle from the SwiftPM executable and ad-hoc signs it.
# This is the answer to POC question 1: building and running a macOS app needs
# no Apple Developer account, no paid program, and no notarization — only a
# local Xcode toolchain. The codesign summary printed at the end is the evidence.
#
# usage: scripts/build-app.sh [--debug]
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

configuration="release"
if [[ "${1:-}" == "--debug" ]]; then
    configuration="debug"
fi

app="$root/build/Island.app"
bundle_id="com.binyanli.island.poc"
version="0.1.0"

swift build -c "$configuration"
executable="$(swift build -c "$configuration" --show-bin-path)/Island"

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$executable" "$app/Contents/MacOS/Island"

# The VS Code extension island installs on launch (VSCodeExtensionInstaller).
vscode_extension_version="$(/usr/bin/plutil -extract version raw -o - "$root/vscode-extension/package.json")"
"$root/scripts/build-vscode-extension.sh" "$app/Contents/Resources/island-vscode.vsix" >/dev/null

cat >"$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Island</string>
    <key>CFBundleDisplayName</key>
    <string>island</string>
    <key>CFBundleIdentifier</key>
    <string>$bundle_id</string>
    <key>CFBundleExecutable</key>
    <string>Island</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$version</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <!-- Accessory app: no Dock icon, no menu bar. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Shown once per terminal app the first time island focuses one of its tabs. -->
    <key>NSAppleEventsUsageDescription</key>
    <string>island brings the terminal tab running a finished agent task to the front.</string>
    <key>IslandVSCodeExtensionVersion</key>
    <string>$vscode_extension_version</string>
</dict>
</plist>
PLIST

# Ad-hoc signature ("-"): the app is signed by the build machine, not by an
# Apple identity, which is enough for Gatekeeper to let it run locally.
codesign --force --sign - "$app"
codesign --verify --verbose=1 "$app"

echo "built $app"
codesign -dvv "$app" 2>&1 | grep -E "^(Identifier|Format|CodeDirectory|Signature|TeamIdentifier)" || true
