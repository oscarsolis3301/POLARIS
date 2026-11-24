# presence-guard — is the owner here, or away? (ops/contracts/away.md § 1–2, Executable checks B1)
# Canned hook payloads through kit/ops/hooks/presence-guard.sh --test, which prints ONE word after
# performing the same state writes the real hook does. Each case names a session; the state files it
# leaves behind are shown as present/absent and by their first line (never the approval's epoch).
# HERMETIC: HOME, USERPROFILE and POLARIS_AWAKE_HOME are faked together under one mktemp -d, so the
# real ~/.claude is never read or written. No sha, path or time is printed.
H="$(pwd)/kit/ops/hooks/presence-guard.sh"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"; mkdir -p "$HOME"
S="$HOME/.claude/polaris/model-state"
P() { # P <event> <sid> <tool> [mode] — one payload, the word, the rc
  local m=''; [ -n "${4:-}" ] && m=",\"permission_mode\":\"$4\""
  printf '{"session_id":"%s","transcript_path":"x","cwd":"x"%s,"hook_event_name":"%s","tool_name":"%s","tool_input":{"q":"a \\"quoted\\" permission_mode"}}' "$2" "$m" "$1" "$3" \
    | bash "$H" --test 2>"$FIX/err"; echo "  rc=$? stderr=$(wc -c < "$FIX/err" | tr -d ' ')"
}
A() { [ -f "$S/$1.approved" ] && echo "  $1.approved: present" || echo "  $1.approved: absent"; }
M() { if [ -f "$S/$1.mode" ]; then echo "  $1.mode: $(head -n 1 "$S/$1.mode")"; else echo "  $1.mode: absent"; fi; }

echo '--- no approval on record: here, whatever the mode'
P PreToolUse s1 AskUserQuestion auto; A s1
echo '--- ExitPlanMode went through (PostToolUse): the approval is on record'
P PostToolUse s1 ExitPlanMode auto; A s1
echo '--- approved + auto, the question tool: refused'
P PreToolUse s1 AskUserQuestion auto
echo '--- approved + bypassPermissions: refused'
P PreToolUse s1 AskUserQuestion bypassPermissions
echo '--- approved + dontAsk: refused'
P PreToolUse s1 AskUserQuestion dontAsk
echo '--- approved + default: here'
P PreToolUse s1 AskUserQuestion default; M s1
echo '--- a Bash call in auto: no opinion, the mode is recorded'
P PreToolUse s1 Bash auto; M s1
echo '--- no permission_mode after a recorded auto: the recorded one counts, refused'
P PreToolUse s1 AskUserQuestion
echo '--- mode plan: here, and the old approval is gone'
P PreToolUse s1 AskUserQuestion plan; A s1; M s1
echo '--- plan -> auto (the plan was approved by the mode change): on record again, refused'
P UserPromptSubmit s1 '' auto; A s1; M s1
P PreToolUse s1 AskUserQuestion auto
echo '--- a second approval keeps the first one and its slugs'
printf 'away\n' >> "$S/s1.approved"
P PostToolUse s1 ExitPlanMode auto; echo "  s1.approved line 2: $(sed -n 2p "$S/s1.approved")"
echo '--- garbage, empty, no event: allow:error, rc 0'
printf 'not json at all' | bash "$H" --test; echo "  rc=$?"
printf '' | bash "$H" --test; echo "  rc=$?"
printf '{"session_id":"s9"}' | bash "$H" --test; echo "  rc=$?"
echo '--- session id ../x: nothing written'
P PostToolUse ../x ExitPlanMode auto
echo "  files under home named x: $(find "$FIX" -name 'x.*' | wc -l | tr -d ' ')"
echo '--- HOME unset: allow:error'
( unset HOME; P PreToolUse s1 AskUserQuestion auto )
echo '--- the real output: the pinned deny line, and nothing at all when here'
printf '{"session_id":"s1","permission_mode":"auto","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{}}' | bash "$H"; echo "rc=$?"
printf '{"session_id":"s2","permission_mode":"auto","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","tool_input":{}}' | bash "$H" | wc -c | tr -d ' '
echo '--- lib/presence.sh under set -eu: bind appends once, only to an approval on record; covers needs away + the slug'
(
  set -eu
  . kit/ops/lib/presence.sh
  r() { if "$@"; then echo "  $* rc=0"; else echo "  $* rc=1"; fi; }
  export CLAUDE_CODE_SESSION_ID=s1
  _presence_bind away; _presence_bind ui-kit; _presence_bind ui-kit; _presence_bind 'bad slug'
  echo "  s1.approved slugs: $(sed -n '2,$p' "$S/s1.approved" | tr '\n' ' ')"
  r _presence_covers ui-kit; r _presence_covers nope; r _presence_away
  export CLAUDE_CODE_SESSION_ID=s3
  _presence_bind away; echo "  s3.approved: $([ -f "$S/s3.approved" ] && echo present || echo absent)"
  r _presence_covers away
  printf 'default\n' > "$S/s1.mode"; export CLAUDE_CODE_SESSION_ID=s1
  r _presence_covers ui-kit; r _presence_away
  unset CLAUDE_CODE_SESSION_ID; _presence_state; echo "  no sid: $PRESENCE / $PRESENCE_WHY"
)
echo "  subshell rc=$?"
# --- walk-away § 1, § 4.1, § 4.4 (T-319): the approval ARMS the run in the primary the cwd names.
#     The cwd is sent JSON-escaped (every / as \\), the way Claude Code sends a Windows one.
R="$FIX/repo"; mkdir -p "$R/ops/board"; RUN="$R/.polaris/run"
ESC="$(printf '%s' "$R" | sed 's#/#\\\\#g')"
PA() { # PA <event> <sid> <tool> <mode> <cwd> [prompt] — one payload with a real cwd, the word
  local pr=''; [ -n "${6:-}" ] && pr=",\"prompt\":\"$6\""
  printf '{"session_id":"%s","transcript_path":"x","cwd":"%s","permission_mode":"%s","hook_event_name":"%s","tool_name":"%s"%s,"tool_input":{}}' \
    "$2" "$5" "$4" "$1" "$3" "$pr" | bash "$H" --test 2>"$FIX/err"; echo "  rc=$? stderr=$(wc -c < "$FIX/err" | tr -d ' ')"
}
AR() { # the armed file, line by line, the epoch shown only as its shape
  if [ -f "$RUN/$1.armed" ]; then
    echo "  $1.armed line 1: $(sed -n 1p "$RUN/$1.armed" | sed 's/^[0-9][0-9]*$/<epoch>/')"
    echo "  $1.armed line 2: [$(sed -n 2p "$RUN/$1.armed")]"
    echo "  $1.armed line 3: $(sed -n 3p "$RUN/$1.armed")"
  else echo "  $1.armed: absent"; fi
}
echo '--- armed: ExitPlanMode in a repo with a board writes <primary>/.polaris/run/<sid>.armed with the slug'
printf '1700000000\nwalk-away\n' > "$S/a1.approved"
PA PostToolUse a1 ExitPlanMode auto "$ESC"; AR a1
echo '--- armed: a second approval keeps the armed file as it is'
printf '1700000000\nwalk-away\nreentries 2\n' > "$RUN/a1.armed"
PA PostToolUse a1 ExitPlanMode auto "$ESC"; AR a1
echo '--- armed: mode plan removes it beside the approval'
PA PreToolUse a1 Bash plan "$ESC"; A a1; AR a1
echo '--- armed: plan -> auto is the other approval path, and arms again (no slug on record yet)'
PA UserPromptSubmit a1 '' auto "$ESC"; A a1; AR a1
echo '--- armed: a worktree cwd arms its primary'
PA PostToolUse a2 ExitPlanMode auto "$R/.polaris/wt/T-1"; AR a2
rm -f "$RUN/a2.armed"
echo '--- armed: no board under the cwd, nothing armed'
PA PostToolUse a3 ExitPlanMode auto "$FIX/home"; AR a3
echo "  run dirs under home: $(find "$FIX/home" -name run -type d | wc -l | tr -d ' ')"
echo '--- re-entry: reentry unset (session) — the prefix means nothing'
printf '%s\nwalk-away\nreentries 0\n' "$(date +%s)" > "$RUN/a1.armed"
PA UserPromptSubmit r1 '' auto "$ESC" "POLARIS re-entry: run bash ops/polaris pulse --reenter"; A r1
echo '--- re-entry: reentry: desktop — the fresh session inherits the approval and the slug'
printf 'reentry: desktop\n' > "$R/ops/CONVENTIONS.md"
PA UserPromptSubmit r1 '' auto "$ESC" "POLARIS re-entry: run bash ops/polaris pulse --reenter"; A r1
echo "  r1.approved line 2: $(sed -n 2p "$S/r1.approved")"
PA PreToolUse r1 AskUserQuestion auto "$ESC"
echo '--- re-entry: another prompt is no re-entry'
PA UserPromptSubmit r2 '' auto "$ESC" "keep going"; A r2
echo '--- re-entry: reentries at reentry_max (3) — refused'
printf '%s\nwalk-away\nreentries 3\n' "$(date +%s)" > "$RUN/a1.armed"
PA UserPromptSubmit r3 '' auto "$ESC" "POLARIS re-entry: go"; A r3
echo '--- re-entry: the armed run is older than reentry_hours (12) — refused'
printf '1700000000\nwalk-away\nreentries 0\n' > "$RUN/a1.armed"
PA UserPromptSubmit r4 '' auto "$ESC" "POLARIS re-entry: go"; A r4
# --- machine-prefs § 4 (T-334): reentry, reentry_hours and reentry_max fall back to this computer's
#     preferences when the repo has no line; a repo line still beats them. The armed run is 2 h old.
printf '%s\nwalk-away\nreentries 0\n' "$(( $(date +%s) - 7200 ))" > "$RUN/a1.armed"
printf 'reentry_hours: 1\n' > "$FIX/prefs"
echo '--- machine prefs: repo reentry: desktop, machine reentry_hours: 1 — the 2 h old run is refused'
POLARIS_PREFS="$FIX/prefs" PA UserPromptSubmit m1 '' auto "$ESC" "POLARIS re-entry: go"; A m1
echo '--- machine prefs: the same with POLARIS_PREFS empty (layer off) — the 12 h default, inherited'
POLARIS_PREFS= PA UserPromptSubmit m2 '' auto "$ESC" "POLARIS re-entry: go"; A m2
echo '--- machine prefs: the repo also says reentry_hours: 12 — the repo line wins, inherited'
printf 'reentry: desktop\nreentry_hours: 12\n' > "$R/ops/CONVENTIONS.md"
POLARIS_PREFS="$FIX/prefs" PA UserPromptSubmit m3 '' auto "$ESC" "POLARIS re-entry: go"; A m3
echo '--- machine prefs: no repo line at all, the machine file says reentry: desktop — inherited'
: > "$R/ops/CONVENTIONS.md"; printf 'reentry: desktop\n' > "$FIX/prefs"
POLARIS_PREFS="$FIX/prefs" PA UserPromptSubmit m4 '' auto "$ESC" "POLARIS re-entry: go"; A m4
echo '--- machine prefs: the machine file says reentry_max: 0 — refused'
printf 'reentry: desktop\nreentry_max: 0\n' > "$FIX/prefs"
POLARIS_PREFS="$FIX/prefs" PA UserPromptSubmit m5 '' auto "$ESC" "POLARIS re-entry: go"; A m5
