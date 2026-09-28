#!/usr/bin/env bash
# Runs island against seeded, fake agent sessions so a demo can be recorded
# without showing any real session on this machine.
#
#   ./scripts/demo.sh            # build/Island.app must exist (scripts/build-app.sh)
#   ./scripts/demo.sh --check    # finish every task at once, print what island detects, no window
#
# Quit any other running island first, or both will pop up. The fake tasks
# finish one by one a few seconds apart; Ctrl-C stops island and cleans up.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="$root/build/Island.app/Contents/MacOS/Island"
[[ -x "$app" ]] || { echo "demo: build the app first: scripts/build-app.sh" >&2; exit 1; }

demo="$(cd "$(mktemp -d /tmp/island-demo.XXXXXX)" && pwd -P)" # lsof reports /private/tmp
pids=()
cleanup() {
    kill "${pids[@]}" 2>/dev/null || true
    rm -rf "$demo"
}
trap cleanup EXIT INT TERM

now() { date -u +%Y-%m-%dT%H:%M:%S.000Z; }

# A long-lived stand-in process whose pid / name / cwd the agent sources check
# to decide a session is still open.
standin() { # <name> <cwd>
    mkdir -p "$demo/bin"
    cp /bin/sleep "$demo/bin/$1"
    codesign --force --sign - "$demo/bin/$1" 2>/dev/null # a copied system binary is killed otherwise
    (cd "$2" && exec "$demo/bin/$1" 3600) &
    last=$!
    pids+=("$last")
}

claude_ids=()
claude_session() { # <project> <title> <prompt>
    local cwd="$demo/Repos/$1" id
    id="$(uuidgen | tr 'A-Z' 'a-z')"
    mkdir -p "$cwd" "$demo/.claude/sessions" "$demo/.claude/projects/$1"
    standin claude "$cwd"
    printf '{"pid":%d,"sessionId":"%s","cwd":"%s","name":"%s","status":"busy","entrypoint":"cli","startedAt":%d000,"updatedAt":%d000}\n' \
        "$last" "$id" "$cwd" "$2" "$(date +%s)" "$(date +%s)" \
        >"$demo/.claude/sessions/$last.json"
    printf '{"type":"user","message":{"role":"user","content":"%s"}}\n{"type":"ai-title","aiTitle":"%s"}\n' \
        "$3" "$2" >"$demo/.claude/projects/$1/$id.jsonl"
    claude_ids+=("$demo/.claude/projects/$1/$id.jsonl")
}
claude_finish() { # <transcript>
    printf '{"type":"system","subtype":"turn_duration","timestamp":"%s"}\n' "$(now)" >>"$1"
}

pi_files=()
pi_session() { # <project> <prompt>
    local cwd="$demo/Repos/$1" file
    mkdir -p "$cwd" "$demo/.pi/agent/sessions/$1"
    standin pi "$cwd"
    file="$demo/.pi/agent/sessions/$1/$(date -u +%Y-%m-%dT%H-%M-%S)_$(uuidgen | tr 'A-Z' 'a-z').jsonl"
    printf '{"type":"session","id":"%s","timestamp":"%s","cwd":"%s"}\n{"type":"message","id":"m1","timestamp":"%s","message":{"role":"user","content":"%s"}}\n' \
        "$(uuidgen | tr 'A-Z' 'a-z')" "$(now)" "$cwd" "$(now)" "$2" >"$file"
    pi_files+=("$file")
}
pi_finish() { # <session file>
    printf '{"type":"message","id":"m2","timestamp":"%s","message":{"role":"assistant","stopReason":"stop","content":[{"type":"text","text":"done"}]}}\n' \
        "$(now)" >>"$1"
}

claude_session api-server "Fix flaky token refresh test" "the refresh test fails on CI"
pi_session web-app "Add dark mode to the settings page"
claude_session infra "Migrate CI to GitHub Actions" "move us off Travis"
claude_session blog "Draft release notes for v2.3" "write the v2.3 notes"

if [[ "${1:-}" == "--check" ]]; then
    for file in "${claude_ids[@]}"; do claude_finish "$file"; done
    pi_finish "${pi_files[0]}"
    ISLAND_AGENT_HOME="$demo" "$app" --scan-agents
    ISLAND_AGENT_HOME="$demo" "$app" --live-sessions
    exit 0
fi

ISLAND_AGENT_HOME="$demo" ISLAND_OVERLAY_SECONDS="${ISLAND_OVERLAY_SECONDS:-4}" "$app" &
pids+=($!)
echo "demo: island running on $demo; tasks finish every ${DEMO_GAP:-7}s"

gap="${DEMO_GAP:-7}"
sleep "$gap"; claude_finish "${claude_ids[1]}"
sleep "$gap"; pi_finish "${pi_files[0]}"
sleep "$gap"; claude_finish "${claude_ids[0]}"
sleep "$gap"; claude_finish "${claude_ids[2]}"
echo "demo: all tasks finished; Ctrl-C to stop"
wait
