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
