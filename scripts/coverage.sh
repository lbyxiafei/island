#!/usr/bin/env bash
#
# Refresh coverage.txt with the *line* coverage of the non-excluded sources.
#
# Paths listed in coverage.config are dropped from the total; every entry is
# justified in hai/CONTEXT.md. The number written is what the coverage gate in
# `make verify` compares against coverage-baseline.txt.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if ! swift test --enable-code-coverage >"$log" 2>&1; then
    cat "$log" >&2
    exit 1
fi

executable="$(find .build -type d -name '*.xctest' -path '*/debug/*' | head -1)/Contents/MacOS/IslandPackageTests"
if [[ ! -x "$executable" ]]; then
    echo "coverage: test binary not found at $executable" >&2
    exit 1
fi

profile="$(find .build -type f -name 'default.profdata' | head -1)"
if [[ -z "$profile" ]]; then
    echo "coverage: default.profdata not found; run swift test --enable-code-coverage" >&2
    exit 1
fi

exclude="$(
    grep -vE '^\s*(#|$)' coverage.config \
        | paste -sd '|' -
)"

xcrun llvm-cov export \
    -summary-only \
    -instr-profile="$profile" \
    -ignore-filename-regex="$exclude" \
    "$executable" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["totals"]["lines"]["percent"])' \
    >coverage.txt

cat coverage.txt
