#!/usr/bin/env bash
#
# Ships a version to Homebrew:
#   brew install --cask lbyxiafei/tap/island
#
# The source repo stays private, so the dmg lives in the public tap repo
# ($ISLAND_TAP, default lbyxiafei/homebrew-tap) as release "island-v<version>",
# next to the cask Casks/island.rb that points at it. This repo gets tag v<version>.
#
# Run from a clean master that is already pushed; needs everything
# scripts/release.sh needs, plus a logged-in `gh`.
#
# usage: scripts/publish.sh <version>      e.g. scripts/publish.sh 0.2.0
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

version="${1:-}"
tap="${ISLAND_TAP:-lbyxiafei/homebrew-tap}"
release_tag="island-v$version"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "usage: scripts/publish.sh <major.minor.patch>" >&2
    exit 2
fi
if [[ -n "$(git status --porcelain)" ]]; then
    echo "publish: working tree is not clean" >&2
    exit 1
fi
if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/master)" ]]; then
    echo "publish: HEAD is not origin/master; merge and push first" >&2
    exit 1
fi
if git rev-parse -q --verify "refs/tags/v$version" >/dev/null ||
    gh release view "$release_tag" --repo "$tap" >/dev/null 2>&1; then
    echo "publish: $version is already released" >&2
    exit 1
fi

"$root/scripts/release.sh" "$version"
dmg="$root/build/dist/island-$version.dmg"
sha="$(shasum -a 256 "$dmg" | awk '{print $1}')"

checkout="$(mktemp -d)"
trap 'rm -rf "$checkout"' EXIT
gh repo clone "$tap" "$checkout" -- --quiet
mkdir -p "$checkout/Casks"
cat >"$checkout/Casks/island.rb" <<CASK
cask "island" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/$tap/releases/download/island-v#{version}/island-#{version}.dmg"
  name "island"
  desc "Pops up when a local AI agent (Claude Code, Codex, pi) finishes a task"
  homepage "https://github.com/$tap"

  depends_on macos: :ventura

  app "Island.app"

  uninstall quit: "com.commallama.island"

  zap trash: "~/Library/Preferences/com.commallama.island.plist"
end
CASK

gh release create "$release_tag" "$dmg" --repo "$tap" \
    --title "island $version" --notes "brew install --cask ${tap%%/homebrew-*}/${tap#*/homebrew-}/island"
git -C "$checkout" add Casks/island.rb
git -C "$checkout" commit --quiet -m "island $version"
git -C "$checkout" push --quiet
git tag "v$version"
git push --quiet origin "v$version"
echo "publish: island $version -> https://github.com/$tap/releases/tag/$release_tag"
