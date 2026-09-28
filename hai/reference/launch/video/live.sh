#!/bin/bash
# Real-interaction demo: real Terminal windows + tmux, fake agent processes, the demo
# island, real clicks/keys, recorded by bin/rec (only these windows). NOREC=1 = rehearsal.
L=/private/tmp/claude-501/-Users-binyanli-Repos-island/aa561078-77b8-4473-910a-84bcae8eadca/scratchpad/live
V=$L/../video
APP=/Users/binyanli/Repos/.worktree/island-readme-bilingual/build/Island.app/Contents/MacOS/Island
DOM=com.commallama.island
demo=$(cd "$(mktemp -d /tmp/island-live.XXXXXX)" && pwd -P); S=$demo/scripts
X0=0; REC_W=1920; REC_H=1080
log() { echo "[$(date +%T)] $*"; }
osa() { osascript -e "$1"; }
key() { osa "tell application \"System Events\" to $1"; }

defaults export $DOM $L/prefs-backup.plist
IME=$($L/bin/ime)
cleanup() {
  log cleanup
  pkill -f "$demo/scripts" ; tmux kill-session -t island-demo 2>/dev/null
  pkill -f "$APP"; sleep 1
  for w in $WINS; do osa "tell application \"Terminal\" to close window id $w" 2>/dev/null; done
  defaults import $DOM $L/prefs-backup.plist
  $L/bin/ime "$IME"
  open /Users/binyanli/Repos/island/build/Island.app
  osa 'quit app "Terminal"'; sleep 1
  defaults import com.apple.Terminal $L/term-backup.plist
  rm -rf "$demo"
}
trap cleanup EXIT
pro() { osa "tell application \"Terminal\" to $1 settings set \"Pro\""; }

python3 $L/scripts.py $S
mk() { mkdir -p "$demo/Repos/$1"; echo "$demo/Repos/$1"; }
API=$(mk api-server); WEB=$(mk web-app); INFRA=$(mk infra); BLOG=$(mk blog); APPD=$(mk ios-app)
mkdir -p $demo/.claude/sessions $demo/.claude/projects/p $demo/.pi/agent/sessions/web-app $demo/.codex

# Codex: one thread, its turn completes later
CX=019a3c1e-7b2d-7f10-9c55-4e2a8d1f6b30
sqlite3 $demo/.codex/state_5.sqlite "create table threads(id text, name text, title text, cwd text, source text, archived int, updated_at_ms int);
  insert into threads values('$CX','Add offline mode to the sync engine','add offline mode','$APPD','vscode',0,0);"
sqlite3 $demo/.codex/thread_history_1.sqlite "create table thread_turns(thread_id text, status text, completed_at int);
  create table thread_items(thread_id text, item_type text, item_json text, rollout_ordinal int);"

# pi session file
PIF=$demo/.pi/agent/sessions/web-app/$(date -u +%Y-%m-%dT%H-%M-%S)_5b1e0c3a-2f7d-4a61-9d0e-8c3f1a2b4d5e.jsonl
echo "{\"type\":\"session\",\"id\":\"5b1e0c3a-2f7d-4a61-9d0e-8c3f1a2b4d5e\",\"timestamp\":\"$(date -u +%FT%T.000Z)\",\"cwd\":\"$WEB\"}
{\"type\":\"message\",\"id\":\"m1\",\"timestamp\":\"$(date -u +%FT%T.000Z)\",\"message\":{\"role\":\"user\",\"content\":\"Add dark mode to the settings page\"}}" > $PIF

# prefs for the recording: default hotkey, long popup, hints, Midnight theme
defaults write $DOM IslandHotkeyText "cmd+ctrl+,"
defaults write $DOM IslandPopupSeconds -float 120
defaults write $DOM IslandOverlayShowsHints -bool true
defaults write $DOM IslandOverlayTheme midnight

# terminals: remember existing Terminal windows so the recorder excludes them
osa 'quit app "Terminal"'; sleep 1
defaults import com.apple.Terminal $L/term-demo.plist
PRE=$(osa 'tell application "Terminal" to get id of windows' | tr -d ' ')
osa 'tell application "Terminal"
  set s to settings set "Pro"
  set font name of s to "Menlo"
  set font size of s to 18
  set title displays window size of s to false
end tell'
tmux new-session -d -s island-demo -n api-server -c "$API" "$L/bin/claude $S/api-server.txt"
tmux new-window -t island-demo -n web-app -c "$WEB" "$L/bin/pi $S/web-app.txt"
for o in "status-style bg=#161a28,fg=#8c93b3" "status-left ''" "status-right ''" "status-justify left" \
         "window-status-format ' #I #W '" "window-status-current-format '#[bg=#8f9bff,fg=#0b0d14,bold] #I #W '" \
         "set-titles on" "set-titles-string '#W — tmux'" "automatic-rename off"; do eval tmux set -t island-demo $o; done
for w in 1 2; do
  tmux setw -t island-demo:$w window-status-format ' #I #W '
  tmux setw -t island-demo:$w window-status-current-format '#[bg=#8f9bff,fg=#0b0d14,bold] #I #W '
done
term() { # <command> <l> <t> <r> <b>
  osa "tell application \"Terminal\"
    set t to do script \"clear; $1\"
    set current settings of t to settings set \"Pro\"
    set w to first window whose selected tab is t
    set bounds of w to {$2, $3, $4, $5}
    return id of w
  end tell"
}
WINS=""
WB=$(term "cd $INFRA && exec $L/bin/claude $S/infra.txt" 930 330 1840 1030); WINS="$WINS $WB"
WA=$(term "cd $API && exec tmux attach -t island-demo" 80 170 1000 900); WINS="$WINS $WA"
(cd $BLOG && exec $L/bin/claude $S/blog.txt > /dev/null 2>&1) &
osa 'tell application "Finder" to activate'
sleep 1.5
claude_session() { # <name> <cwd> <title>
  local pid; pid=$(pgrep -f "$S/$1.txt" | head -1)
  echo "{\"pid\":$pid,\"sessionId\":\"sid-$1\",\"cwd\":\"$2\",\"name\":\"$3\",\"status\":\"busy\",\"entrypoint\":\"cli\"}" > $demo/.claude/sessions/$pid.json
  printf '{"type":"user","message":{"role":"user","content":"x"}}\n{"type":"ai-title","aiTitle":"%s"}\n' "$3" > $demo/.claude/projects/p/sid-$1.jsonl
}
claude_session api-server "$API" "Fix flaky token refresh test"
claude_session infra "$INFRA" "Migrate CI to GitHub Actions"
claude_session blog "$BLOG" "Draft release notes for v2.3"
finish() { # <name>
  touch $S/$1.done
  if [ "$1" = web-app ]; then
    echo "{\"type\":\"message\",\"id\":\"m2\",\"timestamp\":\"$(date -u +%FT%T.000Z)\",\"message\":{\"role\":\"assistant\",\"stopReason\":\"stop\",\"content\":[{\"type\":\"text\",\"text\":\"done\"}]}}" >> $PIF
  else
    echo "{\"type\":\"system\",\"subtype\":\"turn_duration\",\"timestamp\":\"$(date -u +%FT%T.000Z)\"}" >> $demo/.claude/projects/p/sid-$1.jsonl
  fi
  log "finished $1"
}

ISLAND_AGENT_HOME=$demo $APP > $L/island.log 2>&1 &
sleep 3
IP=$(pgrep -f "$APP" | head -1); TP=$(pgrep -x Terminal | head -1)
EXCL=$(echo "$PRE" | tr -d '\n')
if [ -z "$NOREC" ]; then
  $L/bin/rec $L/raw.mov $X0 0 $REC_W $REC_H ${REC_SECS:-34} "$IP,$TP" "$EXCL" > $L/rec.log 2>&1 &
  RECPID=$!
  until grep -q recording $L/rec.log 2>/dev/null || grep -q error $L/rec.log 2>/dev/null; do sleep 0.2; done
  cat $L/rec.log
fi
$L/bin/ime com.apple.keylayout.ABC || $L/bin/ime com.apple.keylayout.US
$L/bin/mouse move 1700 1000 0.3
log "timeline start"
sleep 3.5; finish infra
sleep 3.5; finish web-app
sleep 2.5; sqlite3 $demo/.codex/thread_history_1.sqlite "insert into thread_turns values('$CX','completed',$(date +%s));"; log "finished codex"
sleep 2.5; finish api-server; finish blog
[ -n "$NOREC" ] && { sleep 1; screencapture -x -o -l$WA $L/peek/A.png; screencapture -x -o -l$WB $L/peek/B.png; }
sleep 3.5
# click the "Migrate CI" row (last row) with the real mouse
read id layer px py pw ph < <($V/wins $IP | sort -k6 -n | tail -1)
RX=$((px + pw / 2 - 60)); RY=$((py + ph - 36))
log "panel $px $py $pw $ph -> click $RX $RY"
$L/bin/mouse move $RX $RY 1.1; sleep 0.7; $L/bin/mouse click $RX $RY
sleep 3
$L/bin/mouse move 1700 1000 0.8
sleep 1
key 'keystroke "," using {command down, control down}'; sleep 1.4
for c in f l a k y; do key "keystroke \"$c\""; sleep 0.22; done
sleep 1.2; key 'key code 36'
sleep 4.5
log "timeline end"
[ -z "$NOREC" ] && wait $RECPID
