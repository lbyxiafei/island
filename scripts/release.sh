#!/usr/bin/env bash
#
# Builds a notarized island for other people's Macs:
#   build/dist/island-<version>.dmg   (drag Island.app to Applications)
#
# Needs a "Developer ID Application" certificate in the keychain and a
# notarytool keychain profile (default "notary", override $ISLAND_NOTARY_PROFILE).
# One-time setup of both: dotfiles llm/skill/macos-release.
#
# Steps: sign (build-app.sh) -> notarize + staple the app -> pack the dmg ->
# sign + notarize + staple the dmg -> check both the way Gatekeeper will.
# Publishing the dmg is scripts/publish.sh.
#
# usage: scripts/release.sh <version>      e.g. scripts/release.sh 0.2.0
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

version="${1:-}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: scripts/release.sh <major.minor.patch>" >&2
    exit 2
fi
profile="${ISLAND_NOTARY_PROFILE:-notary}"
identity="${ISLAND_SIGN_IDENTITY:-$(
    security find-identity -v -p codesigning 2>/dev/null |
        sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1
)}"
if [[ -z "$identity" || "$identity" == "-" ]]; then
    echo "release: no Developer ID Application certificate in the keychain" >&2
    exit 1
fi
if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
    echo "release: notarytool profile \"$profile\" is missing or rejected" >&2
    exit 1
fi

ISLAND_SIGN_IDENTITY="$identity" ISLAND_VERSION="$version" "$root/scripts/build-app.sh"
app="$root/build/Island.app"
dist="$root/build/dist"
rm -rf "$dist"
mkdir -p "$dist"

# Submits a file and waits; fails with Apple's log unless it was accepted.
notarize() {
    local file="$1" result id status
    result="$(xcrun notarytool submit "$file" --keychain-profile "$profile" --wait --output-format json)"
    id="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["id"])' "$result")"
    status="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["status"])' "$result")"
    echo "notarization $id: $status"
    if [[ "$status" != "Accepted" ]]; then
        xcrun notarytool log "$id" --keychain-profile "$profile" >&2 || true
        exit 1
    fi
}

# 1. The app itself, so it is stapled even when copied out of the dmg.
ditto -c -k --keepParent "$app" "$dist/Island.zip"
notarize "$dist/Island.zip"
rm "$dist/Island.zip"
xcrun stapler staple "$app"

# 2. The dmg: the app plus an Applications shortcut to drag it onto.
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Island.app"
ln -s /Applications "$staging/Applications"
dmg="$dist/island-$version.dmg"
hdiutil create -quiet -volname "island" -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
codesign --force --timestamp --sign "$identity" "$dmg"
notarize "$dmg"
xcrun stapler staple "$dmg"

# 3. What Gatekeeper on another Mac will say.
spctl --assess --type execute --verbose=2 "$app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
xcrun stapler validate "$dmg"
shasum -a 256 "$dmg"
echo "release: $dmg"
