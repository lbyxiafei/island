#!/usr/bin/env bash
#
# Dependency-direction gate.
#
# SwiftPM refuses to build cyclic *target* dependencies, so the remaining risk
# is an illegal dependency inside the code: the pure-logic layer reaching into
# UI frameworks. IslandCore must stay platform-agnostic (and therefore testable
# off the main actor), so AppKit / SwiftUI / Carbon imports are rejected there.
#
# usage: scripts/check-layering.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

forbidden='^import (AppKit|SwiftUI|Carbon|Carbon\.HIToolbox)\b'
violations="$(grep -rEh "$forbidden" Sources/IslandCore || true)"

if [[ -n "$violations" ]]; then
    echo "layering: IslandCore must not depend on UI frameworks:" >&2
    echo "$violations" >&2
    exit 1
fi

# The executable is allowed a fixed set of *Apple* frameworks. Any other import is a new
# dependency and has to be a conscious, reviewed change (see AGENTS.md `Ask first`).
stray="$(grep -rEh '^import ' Sources/Island --include='*.swift' \
    | grep -vE '^import (AppKit|Foundation|Carbon\.HIToolbox|ServiceManagement|IslandCore)$' || true)"
if [[ -n "$stray" ]]; then
    echo "layering: Sources/Island imports something unexpected:" >&2
    echo "$stray" >&2
    exit 1
fi

echo "layering: ok (IslandCore is UI-free; Island imports only Apple frameworks + IslandCore)"
