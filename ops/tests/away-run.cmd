# away-run — the walk-away seams on the JOINED tree (ops/contracts/walk-away.md § 10, T-327). Each step
# is a real hand-off between two wave-1/2 cards that were built side by side and only meet here:
#   1. presence-guard (T-319) arms the run on an approved ExitPlanMode in auto mode — the armed file
#   2. a --budget 2 job whose shell spawns sleeping children (T-318's watchdog): exit 4, the pinned
#      timed-out line, no child left alive
#   3. the Stop gate (T-319) reads that armed file: work left → block:run twice, the third → allow:stalled
#   4. defer one command (T-318), then finish (T-324) reads the armed file: parked - 1 waiting on you,
#      one ⛔ line, the armed file gone
#   5. pulse (T-318) reads finish's parked file: parked
#
# HERMETIC: the kit is INSTALLED into a throwaway repo under mktemp -d and the fixture's own hooks and
# CLI run; HOME, USERPROFILE, POLARIS_AWAKE_HOME and POLARIS_HEAVY_DIR live inside the fixture. The
# Stop gate's background `notify-gate stall` goes to a stub that records its arguments (polled, never
# slept on). No sha, time, pid or absolute path is printed.
unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID POLARIS_INT_TOKEN POLARIS_HEAVY_TOKEN POLARIS_HEAVY_WAIT
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT POLARIS_HANDOVER_NEXT
KIT_DIR="$(pwd)/kit"
FIX="$(mktemp -d)"
trap 'cd /; rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake" POLARIS_HEAVY_DIR="$FIX/heavy"
mkdir -p "$HOME"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/seed.txt
  git add -A; git commit -qm init
  bash "$KIT_DIR/ops/install.sh" "$R"
  bash ops/polaris init-board
  printf 'handover: auto\nrun_max_tasks: 0\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
echo "installed: $([ -f ops/hooks/presence-guard.sh ] && [ -f ops/hooks/handover-hook.sh ] && echo yes || echo no)"
RUN="$R/.polaris/run"; MS="$HOME/.claude/polaris/model-state"
ESC="$(printf '%s' "$R" | sed 's#/#\\\\#g')"     # the cwd JSON-escaped, the way Claude Code sends a Windows one

echo "== 1. the approval arms the run (presence-guard, ExitPlanMode in auto mode) =="
printf '{"session_id":"aw","transcript_path":"x","cwd":"%s","permission_mode":"auto","hook_event_name":"PostToolUse","tool_name":"ExitPlanMode","tool_input":{}}' "$ESC" \
  | bash ops/hooks/presence-guard.sh --test 2>/dev/null; echo "  rc=$?"
echo "  approved: $([ -f "$MS/aw.approved" ] && echo present || echo absent)"
if [ -f "$RUN/aw.armed" ]; then
  echo "  armed line 1: $(sed -n 1p "$RUN/aw.armed" | sed 's/^[0-9][0-9]*$/<epoch>/')"
  echo "  armed line 3: $(sed -n 3p "$RUN/aw.armed")"
else echo "  armed: absent"; fi

echo "== 2. a hung job: killed at its budget, retried once, exit 4, nothing left behind =="
printf 'sleep 300 & echo $! >> "%s/kids"\nsleep 301 & echo $! >> "%s/kids"\nwait\n' "$FIX" "$FIX" > "$FIX/hang.sh"
bash ops/polaris bg run hang --budget 2 -- sh "$FIX/hang.sh" >/dev/null 2>&1
out="$(bash ops/polaris bg wait hang --max 60 2>&1)"; echo "  wait rc=$?"
printf '%s\n' "$out" | grep '^⛔ hang timed out' | sed -e "s#$FIX#<fix>#g" -e 's#[^ ]*/\.polaris/bg/#<reg>/#g' -e 's/^/  /'
left=0; for k in $(cat "$FIX/kids"); do ps -ef 2>/dev/null | awk -v p="$k" '$2 == p && /sleep/ { f = 1 } END { exit !f }' && left=$((left + 1)); done
echo "  children started: $(grep -c . "$FIX/kids") · alive: $left"

echo "== 3. the Stop gate reads the armed file: work left blocks, the third identical block is a stall =="
STUB="$FIX/stub.sh"; CALLS="$FIX/stub.calls"
printf 'printf "%%s\\n" "$*" >> "%s"\n' "$CALLS" > "$STUB"
mkdir -p "$R/.polaris/handover/aw"; printf '%s\n' "100 done T-1" > "$R/.polaris/handover/aw/last-event"
rs() { printf '{"session_id":"aw","transcript_path":"%s","cwd":"%s","permission_mode":"auto","stop_hook_active":false,"hook_event_name":"Stop","background_tasks":[],"session_crons":[]}' \
         "$FIX/none.jsonl" "$R" | POLARIS_HANDOVER_NEXT="build T-1" POLARIS_HANDOVER_CLI="$STUB" bash ops/hooks/handover-hook.sh --test stop; }
rs | sed 's/^/  /'
rs | sed 's/^/  /'
rs | sed 's/^/  /'
i=0; while [ "$i" -lt 100 ] && [ ! -s "$CALLS" ]; do sleep 0.1; i=$((i + 1)); done
echo "  stalled: $([ -f "$RUN/stalled" ] && echo yes || echo no) · notify: $(sed -n 1p "$CALLS" 2>/dev/null)"
rm -f "$RUN/stalled"     # seen; the close below counts the deferred command alone

echo "== 4. defer one command, then finish: parked, one line waiting, the armed file gone =="
bash ops/polaris defer -m "the release push needs a token" -- git push origin main 2>&1 | sed 's/^/  /'
OUT="$(CLAUDE_SESSION_ID=aw bash ops/polaris finish 2>&1)"; echo "  finish rc=$?"
printf '%s\n' "$OUT" | grep -E '^(⛔ finish: parked|⛔ waiting on you|run: )' | sed -E 's/^run: .*/run: <the run line>/' | sed 's/^/  /'
echo "  armed: $(ls "$RUN"/*.armed 2>/dev/null | wc -l | tr -d ' ') · parked: $(ls "$RUN"/*.parked 2>/dev/null | sed 's#.*/##' | tr '\n' ' ')"

echo "== 5. the pulse reads finish's parked file =="
CLAUDE_CODE_SESSION_ID=aw CLAUDE_SESSION_ID=aw bash ops/polaris pulse 2>&1 | sed -n 1p | sed 's/^/  /'
