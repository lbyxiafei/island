#!/usr/bin/env bash
# Packs vscode-extension/ into a .vsix with the system zip, so island can
# install it without vsce or any npm dependency.
#   usage: scripts/build-vscode-extension.sh <output.vsix>
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
source_dir="$root/vscode-extension"
output="${1:?usage: $0 <output.vsix>}"

field() { /usr/bin/plutil -extract "$1" raw -o - "$source_dir/package.json"; }
name="$(field name)"
publisher="$(field publisher)"
version="$(field version)"
engine="$(field engines.vscode)"

staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/extension"
cp "$source_dir/package.json" "$source_dir/extension.js" "$staging/extension/"

cat >"$staging/[Content_Types].xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension=".json" ContentType="application/json"/><Default Extension=".js" ContentType="application/javascript"/><Default Extension=".vsixmanifest" ContentType="text/xml"/></Types>
XML

cat >"$staging/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="$name" Version="$version" Publisher="$publisher"/>
    <DisplayName>$(field displayName)</DisplayName>
    <Description xml:space="preserve">$(field description)</Description>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="$engine"/>
    </Properties>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code"/>
  </Installation>
  <Dependencies/>
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/>
  </Assets>
</PackageManifest>
XML

rm -f "$output"
mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"
(cd "$staging" && /usr/bin/zip -qrX "$output" "[Content_Types].xml" extension.vsixmanifest extension)
echo "$output"
