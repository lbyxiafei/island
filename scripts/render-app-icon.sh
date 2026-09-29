#!/usr/bin/env bash
#
# Regenerates assets/AppIcon.icns from assets/AppIcon.svg. Run it after
# editing the SVG and commit both; scripts/build-app.sh only copies the .icns.
#
# usage: scripts/render-app-icon.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

swift "$root/scripts/render-app-icon.swift" "$root/assets/AppIcon.svg" "$work/AppIcon.iconset"
iconutil --convert icns --output "$root/assets/AppIcon.icns" "$work/AppIcon.iconset"
echo "render-app-icon: wrote assets/AppIcon.icns"
