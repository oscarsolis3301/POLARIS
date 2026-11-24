# permission-hook — an armed away run never waits on a permission prompt (ops/contracts/walk-away.md
# § 4.3). Canned PermissionRequest / PermissionDenied payloads through kit/ops/hooks/permission-hook.sh
# --test, which prints ONE word after the same state writes the real hook does, plus the raw output
# where its bytes are the contract. The invariant that matters most is asserted by count: no input
# ever yields an "allow" decision. HERMETIC: HOME, USERPROFILE and POLARIS_AWAKE_HOME are faked under
# one mktemp -d; the fixture repo is a dir with an ops/board. No sha, path, time or pid is printed.
H="$(pwd)/kit/ops/hooks/permission-hook.sh"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"
S="$HOME/.claude/polaris/model-state"; R="$FIX/repo"; RUN="$R/.polaris/run"
mkdir -p "$S" "$R/ops/board"
ESC="$(printf '%s' "$R" | sed 's#/#\\\\#g')"       # the cwd as Claude Code sends a Windows one
BASHIN='"tool_name":"Bash","tool_input":{"command":"git push --force origin \"main\"","description":"push"}'
EDITIN='"tool_name":"Edit","tool_input":{"file_path":"src/app.js","old_string":"a","new_string":"b"}'
# P <sub> <event> <sid> <mode> <cwd> <tool fields> [real] — one payload, the word (or the raw bytes)
P() {
  local t='--test' m=''; [ "${7:-}" = real ] && t=''
  [ -n "$4" ] && m=",\"permission_mode\":\"$4\""
  printf '{"session_id":"%s","transcript_path":"x","cwd":"%s"%s,"hook_event_name":"%s",%s}' "$3" "$5" "$m" "$2" "$6" \
    | bash "$H" $t "$1" 2>"$FIX/err"
  echo "  rc=$? stderr=$(wc -c < "$FIX/err" | tr -d ' ')"
}
arm() { mkdir -p "$RUN"; printf '%s\nwalk-away\nreentries 0\n' "${1:-$(date +%s)}" > "$RUN/s1.armed"; }
echo '--- not armed: the dialog opens as always, nothing recorded'
printf '1700000000\nwalk-away\n' > "$S/s1.approved"
P request PermissionRequest s1 auto "$ESC" "$BASHIN"
P denied PermissionDenied s1 auto "$ESC" "$BASHIN"
echo "  denied.tsv: $([ -f "$RUN/denied.tsv" ] && echo present || echo absent)"
echo '--- armed + away (auto, bypassPermissions, dontAsk): denied with the park line'
arm
P request PermissionRequest s1 auto "$ESC" "$BASHIN"
P request PermissionRequest s1 bypassPermissions "$ESC" "$EDITIN"
P request PermissionRequest s1 dontAsk "$ESC" "$BASHIN"
echo '--- armed + away, the mode from <sid>.mode when the payload has none'
printf 'auto\n' > "$S/s1.mode"
P request PermissionRequest s1 '' "$ESC" "$BASHIN"
echo '--- armed, owner here: default mode, no approval on record, a bad session id'
P request PermissionRequest s1 default "$ESC" "$BASHIN"
P request PermissionRequest s2 auto "$ESC" "$BASHIN"
P request PermissionRequest ../s1 auto "$ESC" "$BASHIN"
echo '--- armed, but the cwd has no board, or the armed file is stale (older than reentry_hours)'
P request PermissionRequest s1 auto "$FIX/home" "$BASHIN"
arm 1700000000
P request PermissionRequest s1 auto "$ESC" "$BASHIN"
arm
echo '--- a worktree cwd reads its primary'
P request PermissionRequest s1 auto "$R/.polaris/wt/T-1" "$BASHIN"
echo '--- garbage, empty, an unknown subcommand: no opinion, rc 0'
printf 'not json' | bash "$H" --test request; echo "  rc=$?"
printf '' | bash "$H" --test denied; echo "  rc=$?"
printf '{}' | bash "$H" --test bogus; echo "  rc=$?"
echo '--- the real output: the deny JSON (escapes kept intact), and nothing at all when here'
P request PermissionRequest s1 auto "$ESC" "$BASHIN" real
P request PermissionRequest s1 auto "$ESC" "$EDITIN" real
P request PermissionRequest s1 default "$ESC" "$BASHIN" real
python -c "import json,sys; d=json.loads(sys.stdin.read()); print('  json ok:', d['hookSpecificOutput']['decision']['behavior'])" \
  < <(printf '{"session_id":"s1","cwd":"%s","permission_mode":"auto","hook_event_name":"PermissionRequest",%s}' "$ESC" "$BASHIN" | bash "$H" request) | tr -d '\r'
echo '--- denied: armed → one TAB line per denial (epoch, tool, the first 160 chars); never prints'
P denied PermissionDenied s1 auto "$ESC" "$BASHIN"
P denied PermissionDenied s1 default "$ESC" "$EDITIN" real
LONG="$(printf 'x%.0s' $(seq 1 200))"
P denied PermissionDenied s1 auto "$ESC" "\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"echo $LONG\"},\"tool_use_id\":\"t1\",\"reason\":\"[x]\""
sed 's/^[0-9][0-9]*\t/<epoch>|/; s/\t/|/g' "$RUN/denied.tsv" | awk '{ print "  " substr($0, 1, 60) " (" length($0) " chars)" }'
echo '--- never allows: no "allow" decision anywhere in this file or any output above'
printf '  allow decisions in the hook: %s\n' "$(grep -c '"behavior":"allow"' "$H")"
