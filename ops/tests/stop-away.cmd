# stop-away — while the owner is away (ops/contracts/away.md § 3, role-handover.md § v4) a closing
# question with work left is bounced on EVERY stop, stop_hook_active included, with AWAY_SAY and never
# "ask again and you will be let through"; the run's end, a stop mark, an unlicensed stop and every
# "here" state keep today's rung. HERMETIC: the kit is INSTALLED into a mktemp fixture and the
# fixture's own ops/hooks/handover-hook.sh runs; HOME, USERPROFILE and POLARIS_AWAKE_HOME are faked
# together and the state files are written here by hand (away.md § 1 is the whole interface).
KIT_DIR="$(pwd)/kit"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"; mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT
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
HOOK="$R/ops/hooks/handover-hook.sh"
echo "installed: $([ -f "$HOOK" ] && echo yes || echo no)"
MS="$HOME/.claude/polaris/model-state"; TR="$FIX/tr/session.jsonl"; mkdir -p "$MS" "$FIX/tr"
tr_text() { printf '{"type":"assistant","message":{"content":[{"type":"text","text":"%s"}]}}\n' "$1" > "$TR"; }
# $1 sid · $2 permission_mode ('' = none in the payload) · $3 stop_hook_active · $4 next line 1 · $5 = real for the output layer
stop() {
  local d="$R/.polaris/handover/$1" pm='' t='--test'
  mkdir -p "$d"; [ -f "$d/last-event" ] || printf '%s\n' "100 done T-1" > "$d/last-event"
  rm -f "$d/hops" "$d/hopped-event"
  [ -n "$2" ] && pm=",\"permission_mode\":\"$2\""
  [ "${5:-}" = real ] && t=''
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s"%s,"stop_hook_active":%s,"hook_event_name":"Stop"}' \
    "$1" "$TR" "$R" "$pm" "$3" | POLARIS_HANDOVER_NEXT="$4" bash "$HOOK" $t stop
}
printf '%s\n' 1700000000 > "$MS/aw.approved"
tr_text "continue?"
echo "--- away: approved + auto"
stop aw auto false "build T-1"
stop aw auto true "build T-1"
stop aw auto true "integrate"
stop aw bypassPermissions false "promote"
stop aw dontAsk true "build T-1"
echo "hop consumed: $([ -f "$R/.polaris/handover/aw/hopped-event" ] && echo yes || echo no)"
stop aw auto false "finish"
stop aw auto false "tidy"
stop aw auto false "wait"
stop aw auto false "stop"
echo "--- away: the mode from <sid>.mode when the payload has none"
printf '%s\n' auto > "$MS/aw.mode"
stop aw "" false "build T-1"
stop aw "" true "build T-1"
printf '%s\n' default > "$MS/aw.mode"
stop aw "" false "build T-1"
echo "--- away: a stop mark and an unlicensed stop keep today's rung"
tr_text "⛔ blocked — need a key"
stop aw auto true "build T-1"
stop aw auto false "build T-1"
tr_text "continue?"
printf '%s\n' "100 claim T-1" > "$R/.polaris/handover/aw/last-event"
stop aw auto true "build T-1"
rm -f "$R/.polaris/handover/aw/last-event"
echo "--- here: today's ladder"
stop aw default false "build T-1"
stop aw default true "build T-1"
stop aw plan false "build T-1"
stop aw plan true "build T-1"
stop aw acceptEdits false "integrate"
stop nobody auto false "build T-1"
stop nobody auto true "build T-1"
printf '%s\n' 1700000000 > "$MS/a.b.approved"
stop a.b auto false "build T-1"
echo "--- the real output"
out="$(stop aw auto true "build T-1" real)"; echo "$out"
echo "let through: $(printf '%s\n' "$out" | grep -c 'let through')"
out="$(stop aw default false "build T-1" real)"
echo "here let through: $(printf '%s\n' "$out" | grep -c 'ask again and you will be let through')"
# --- walk-away § 4.2 (T-319): THE ARMED RUNG, first in the ladder. <primary>/.polaris/run/aw.armed on
#     disk + away. POLARIS_HANDOVER_CLI is a stub that only records its arguments, so the third
#     block's `notify-gate stall` is observed without running anything; it is polled, never slept on.
RUN="$R/.polaris/run"; mkdir -p "$RUN"; STUB="$FIX/stub.sh"; CALLS="$FIX/stub.calls"
printf 'printf "%%s\\n" "$*" >> "%s"\n' "$CALLS" > "$STUB"
arm() { printf '%s\nwalk-away\nreentries 0\n' "${1:-$(date +%s)}" > "$RUN/aw.armed"; }
BG=',"background_tasks":[{"id":"t1","type":"shell","status":"running","description":"ship","command":"bash ops/polaris bg wait ship-T-1 --done"}],"session_crons":[]'
NOBG=',"background_tasks": [ ],"session_crons":[]'
PULSE=',"background_tasks":[],"session_crons":[{"id":"c1","schedule":"*/30 * * * *","recurring":true,"prompt":"bash ops/polaris pulse, then follow line 1"}]'
OTHER=',"background_tasks":[],"session_crons":[{"id":"c2","schedule":"0 9 * * *","recurring":true,"prompt":"check the build"}]'
# $1 sid · $2 mode · $3 next line 1 · $4 the extra payload fields · $5 = real for the output layer
rs() {
  local t='--test'; [ "${5:-}" = real ] && t=''
  printf '{"session_id":"%s","transcript_path":"%s","cwd":"%s","permission_mode":"%s","stop_hook_active":false,"hook_event_name":"Stop"%s}' \
    "$1" "$TR" "$R" "$2" "${4:-}" | POLARIS_HANDOVER_NEXT="$3" POLARIS_HANDOVER_CLI="$STUB" bash "$HOOK" $t stop
}
calls() { local i=0; while [ "$i" -lt 100 ] && [ ! -s "$CALLS" ]; do sleep 0.1; i=$((i + 1)); done
  printf 'stub calls: %s · %s\n' "$(grep -c . "$CALLS" 2>/dev/null || echo 0)" "$(sed -n 1p "$CALLS" 2>/dev/null)"; }
tr_text "continue?"
printf '%s\n' "100 done T-1" > "$R/.polaris/handover/aw/last-event"
arm
echo "--- armed + away: a background task in flight lets go"
rs aw auto "build T-1" "$BG"
echo "--- armed + away: next says wait / stop — a real wait lets go"
rs aw auto "wait" "$NOBG"
rs aw auto "stop" "$NOBG"
echo "--- armed + away: work left blocks (an empty background_tasks is no task), the third identical block is a stall"
rs aw auto "build T-1" "$NOBG"
rs aw auto "build T-1" "$NOBG"
echo "stalled before the third: $([ -f "$RUN/stalled" ] && echo yes || echo no)"
rs aw auto "build T-1" "$NOBG"
echo "stalled: $([ -f "$RUN/stalled" ] && echo yes || echo no) · $(cut -f2 "$RUN/stalled")"
echo "run-blocks: $(cut -f2- "$R/.polaris/handover/aw/run-blocks" | tr '\t' '|')"
calls
rs aw auto "build T-1" "$NOBG"
calls
echo "--- armed + away: another line 1 is new work, the count starts again"
rs aw auto "integrate" "$NOBG"
echo "run-blocks: $(cut -f2- "$R/.polaris/handover/aw/run-blocks" | tr '\t' '|')"
echo "--- armed + away: no last-event at all (a conductor that completed nothing yet) still blocks"
rm -f "$R/.polaris/handover/aw/last-event" "$R/.polaris/handover/aw/run-blocks"
rs aw auto "build T-1" "$NOBG"
printf '%s\n' "100 done T-1" > "$R/.polaris/handover/aw/last-event"
echo "--- the real output: no pulse cron → the hint; a pulse cron → none; no session_crons field → none"
rm -f "$R/.polaris/handover/aw/run-blocks"; rs aw auto "build T-1" "$OTHER" real
rm -f "$R/.polaris/handover/aw/run-blocks"; rs aw auto "build T-1" "$PULSE" real
rm -f "$R/.polaris/handover/aw/run-blocks"; rs aw auto "finish" "" real
echo "--- pulse_minutes is read from CONVENTIONS"
printf 'handover: auto\nrun_max_tasks: 0\npulse_minutes: 15\n' > ops/CONVENTIONS.md
rm -f "$R/.polaris/handover/aw/run-blocks"; rs aw auto "build T-1" "$NOBG" real | grep -o 'every [0-9]* min'
printf 'handover: auto\nrun_max_tasks: 0\n' > ops/CONVENTIONS.md
echo "--- the rung steps aside: here · away_gate: off · parked · finished · a stale armed file · no armed file"
rm -f "$R/.polaris/handover/aw/run-blocks"
rs aw default "build T-1" "$NOBG"
printf 'handover: auto\nrun_max_tasks: 0\naway_gate: off\n' > ops/CONVENTIONS.md
rs aw auto "build T-1" "$NOBG"
printf 'handover: auto\nrun_max_tasks: 0\n' > ops/CONVENTIONS.md
: > "$RUN/aw.parked"; rs aw auto "build T-1" "$NOBG"; rm -f "$RUN/aw.parked"
touch -t 200001010000 "$RUN/aw.armed"; : > "$R/.polaris/handover/aw/finished"
rs aw auto "build T-1" "$NOBG"; rm -f "$R/.polaris/handover/aw/finished"
arm 1700000000; rs aw auto "build T-1" "$NOBG"
rm -f "$RUN/aw.armed"; rs aw auto "build T-1" "$NOBG"
