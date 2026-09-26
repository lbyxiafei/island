#!/usr/bin/env bash
#
# Assembles a real .app bundle from the SwiftPM executable and signs it.
#
# Signing identity: $ISLAND_SIGN_IDENTITY if set, else the first
# "Developer ID Application" certificate in the keychain (hardened runtime +
# timestamp, ready for scripts/release.sh to notarize), else ad-hoc ("-"),
# which runs on this machine only. Building never needs an Apple account.
#
# Version: $ISLAND_VERSION (e.g. 0.2.0), else 0.0.0 for local builds.
# Releases set it (scripts/publish.sh); `brew upgrade` needs it to grow.
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
bundle_id="com.commallama.island"
version="${ISLAND_VERSION:-0.0.0}"

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
    <string>$version</string>
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

identity="${ISLAND_SIGN_IDENTITY:-$(
    security find-identity -v -p codesigning 2>/dev/null |
        sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1
)}"
entitlements="$root/scripts/Island.entitlements"
if [[ -n "$identity" && "$identity" != "-" ]]; then
    # Notarization requires the hardened runtime and a secure timestamp. A
    # stable identity also keeps macOS permission grants across rebuilds.
    codesign --force --options runtime --timestamp \
        --entitlements "$entitlements" --sign "$identity" "$app"
else
    # Ad-hoc: runs locally; Gatekeeper rejects it anywhere else.
    codesign --force --entitlements "$entitlements" --sign - "$app"
fi
codesign --verify --strict --verbose=1 "$app"

echo "built $app"
codesign -dvv "$app" 2>&1 | grep -E "^(Identifier|Format|CodeDirectory|Signature|TeamIdentifier)" || true
