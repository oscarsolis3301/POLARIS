# runner-path — the Haiku job runner end to end on the JOINED tree (ops/contracts/walk-away.md § 10,
# T-327). Three cards built side by side meet here and nowhere else:
#   1. route (T-321) names the runner: `route --role RUNNER` → its model line and `agent: polaris-runner`
#   2. the guard (T-320) lets exactly that agent through: its Haiku spawn passes the door, its
#      `bg wait` call passes, `ls` is blocked, and a Haiku session that is not the runner gets today's
#      block line, byte for byte
#   3. the agent's own words (T-320's kit/.claude/agents/polaris-runner.md) against the jobs (T-318):
#      the two commands its body names, with a real job name in place of NAME, pass the guard and
#      give the runner what its reply needs — a green job's rc 0 and a red job's rc 1, then the tail
#
# HERMETIC: one throwaway repo under mktemp -d, HOME, USERPROFILE, POLARIS_AWAKE_HOME and
# POLARIS_HEAVY_DIR inside the fixture, the transcripts written here by hand. No sha, time, pid or
# absolute path is printed.
unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID CLAUDE_EFFORT POLARIS_INT_TOKEN POLARIS_HEAVY_TOKEN POLARIS_HEAVY_WAIT
KIT="$(pwd)/kit/ops/polaris"
H="$(pwd)/kit/ops/hooks/model-guard.sh"
AGENT="$(pwd)/kit/.claude/agents/polaris-runner.md"
FIX="$(mktemp -d)"
trap 'cd /; rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake" POLARIS_HEAVY_DIR="$FIX/heavy"
mkdir -p "$HOME" "$FIX/tx/run/subagents"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"

echo "== 1. route names the runner =="
bash "$KIT" route --role RUNNER 2>&1 | sed 's/^/  /'

echo "== 2. the guard lets that agent, and only that command shape, through =="
ST="$HOME/.claude/polaris/model-state"; mkdir -p "$ST"
OPUS=claude-opus-5-5; HAIKU=claude-haiku-4-5
line() { printf '{"type":"assistant","message":{"model":"%s","content":[{"type":"text","text":"ok"}]}}\n' "$1"; }
TP="$FIX/tx/run.jsonl"; line "$OPUS" > "$TP"; printf '%s\n' "$OPUS" > "$ST/run"
line "$HAIKU" > "$FIX/tx/run/subagents/agent-r1.jsonl"
RUNNER=',"agent_id":"r1","agent_type":"polaris-runner"'
G() { # G <label> <tool> <tool_input JSON> [extra top-level fields] — the hook's rc and its words
  printf '{"session_id":"run","transcript_path":"%s","cwd":"%s","hook_event_name":"PreToolUse","tool_name":"%s"%s,"tool_input":%s}' \
    "$TP" "$R" "$2" "${4:-}" "$3" > "$FIX/in"
  bash "$H" < "$FIX/in" > "$FIX/out" 2> "$FIX/err"; rc=$?
  printf '  %-44s rc %s\n' "$1" "$rc"
  while IFS= read -r l; do printf '      %s\n' "$l"; done < "$FIX/err"
  while IFS= read -r l; do printf '      %s\n' "$l"; done < "$FIX/out"
}
G 'spawn polaris-runner, model haiku' Agent '{"description":"d","prompt":"wait on x","subagent_type":"polaris-runner","model":"haiku"}'
G 'runner: bg wait x --max 240' Bash '{"command":"bash ops/polaris bg wait x --max 240"}' "$RUNNER"
G 'runner: ls' Bash '{"command":"ls"}' "$RUNNER"
G 'general-purpose on haiku: bg wait' Bash '{"command":"bash ops/polaris bg wait x --max 240"}' ',"agent_id":"r1","agent_type":"general-purpose"'

echo "== 3. the agent's two commands, on a green job and a red one =="
# The body's commands, read off the agent file itself — a reworded body reds this golden.
CW="$(grep '^bash ops/polaris bg wait NAME' "$AGENT" | tr -d '\r')"
CT="$(grep '^bash ops/polaris bg tail NAME' "$AGENT" | tr -d '\r')"
echo "  the body names: [$CW] · [$CT]"
bash "$KIT" bg run good -- sh -c 'echo built; echo all green' >/dev/null 2>&1
bash "$KIT" bg run bad -- sh -c 'echo built; echo one red >&2; exit 1' >/dev/null 2>&1
for n in good bad; do
  w="${CW//NAME/$n}"; t="${CT//NAME/$n}"
  G "runner: ${w#bash ops/polaris }" Bash "{\"command\":\"$w\"}" "$RUNNER"
  G "runner: ${t#bash ops/polaris }" Bash "{\"command\":\"$t\"}" "$RUNNER"
  rc=2; while [ "$rc" = 2 ]; do bash "$KIT" ${w#bash ops/polaris } >/dev/null 2>&1; rc=$?; done
  echo "  $n: rc=$rc"
  bash "$KIT" ${t#bash ops/polaris } 2>&1 | grep -v '^$' | sed 's/^/    tail: /'
done
