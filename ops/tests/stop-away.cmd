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
