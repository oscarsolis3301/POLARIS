# presence-installed — the presence hook as a project gets it (ops/contracts/away.md § 2.1, § 2.4).
# HERMETIC: a throwaway repo under mktemp -d that ALREADY has a .claude/settings.json — an older
# install's (only the write-guard, no PostToolUse key at all) plus one hook of the owner's own. The
# kit is installed INTO it, and the merge must add the three presence-guard entries (one under a
# NEW event key) and keep the owner's hook. Then the fixture's OWN hook writes the state and the
# fixture's OWN `ops/polaris presence` reads it, once per § 2.4 reason. HOME, USERPROFILE and
# POLARIS_AWAKE_HOME are faked together; no sha, path or time is printed.
KIT_DIR="$(pwd)/kit"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"; mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT CLAUDE_CODE_SESSION_ID
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p .claude
  cat > .claude/settings.json <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR/ops/hooks/ownership-guard.sh\"", "timeout": 20}]}
    ],
    "UserPromptSubmit": [
      {"hooks": [{"type": "command", "command": "bash my-own-prompt-hook.sh"}]}
    ]
  }
}
JSON
  echo x > a.txt
  git add -A; git commit -qm init
) >/dev/null 2>&1
cd "$R"
bash "$KIT_DIR/ops/install.sh" "$R" > "$FIX/out" 2>&1; echo "install rc=$?"
echo "merge report: $(sed -n 's/^✅ \.claude\/settings\.json: hooks + permissions + output style merged (idempotent)\(.*\)$/\1/p' "$FIX/out" | grep -o 'added [^—]*ops/hooks/presence-guard.sh' | sed 's/added .*\(ops\/hooks\/presence-guard.sh\)/added \1/')"
echo "hook file: $([ -f ops/hooks/presence-guard.sh ] && echo installed || echo MISSING) · lib: $([ -f ops/lib/presence.sh ] && echo installed || echo MISSING)"
python - .claude/settings.json <<'PY' | tr -d '\r'   # Windows python prints CRLF
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for ev in ("PreToolUse", "PostToolUse", "UserPromptSubmit"):
    for e in d["hooks"].get(ev, []):
        for h in e.get("hooks", []):
            c = h.get("command", "")
            if "presence-guard.sh" in c or "my-own" in c:
                print("%s  matcher=%s  %s  timeout=%s" % (ev, e.get("matcher", "-"), c.replace("$CLAUDE_PROJECT_DIR/", ""), h.get("timeout", "-")))
PY
H() { # H <event> <tool> <mode> — one payload through the fixture's own hook, as session s1
  local m=''; [ -n "$3" ] && m=",\"permission_mode\":\"$3\""
  printf '{"session_id":"s1"%s,"hook_event_name":"%s","tool_name":"%s","tool_input":{}}' "$m" "$1" "$2" | bash ops/hooks/presence-guard.sh
}
Q() { bash ops/polaris presence; echo "rc=$?"; }
echo '--- no session id'
Q
export CLAUDE_CODE_SESSION_ID=s1
echo '--- a session, no plan approved'
H PreToolUse Bash auto; Q
echo '--- approved, mode not yet on record'
rm -f "$HOME/.claude/polaris/model-state/s1.mode"
H PostToolUse ExitPlanMode ''; Q
echo '--- approved, default mode'
H PreToolUse Bash default; Q
echo '--- approved, auto mode: away'
H UserPromptSubmit '' auto; Q
echo '--- the fixture hook refuses the question while away'
H PreToolUse AskUserQuestion auto | grep -c '"permissionDecision":"deny"'
echo '--- a bad session id is no session id'
CLAUDE_CODE_SESSION_ID=../s1 bash ops/polaris presence
echo '--- walk-away § 4.3 (T-319): the four new registrations, once each, and the fixture has the hook file'
echo "permission hook file: $([ -f ops/hooks/permission-hook.sh ] && echo installed || echo MISSING)"
python - .claude/settings.json <<'PY' | tr -d '\r'
import json, sys
h = json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]
for ev in ("SubagentStop", "StopFailure", "PermissionRequest", "PermissionDenied"):
    cmds = [x["command"].replace("$CLAUDE_PROJECT_DIR/", "") for e in h.get(ev, []) for x in e.get("hooks", [])]
    print("%s  %d entry  %s" % (ev, len(cmds), " | ".join(cmds)))
PY
cp .claude/settings.json "$FIX/before.json"
bash "$KIT_DIR/ops/install.sh" "$R" > "$FIX/out2" 2>&1; echo "re-install rc=$?"
echo "re-install: $(cmp -s "$FIX/before.json" .claude/settings.json && echo 'settings.json byte-identical' || echo 'settings.json REWRITTEN')"
echo "re-install report: $(grep -c 'added ops/hooks/permission-hook.sh' "$FIX/out2") added lines"
echo '--- the fixture hook denies a permission prompt while the run is armed and away (a board dir makes the fixture a primary)'
mkdir -p .polaris/run ops/board; printf '%s\naway\nreentries 0\n' "$(date +%s)" > .polaris/run/s1.armed
printf '{"session_id":"s1","cwd":"%s","permission_mode":"auto","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"}}' "$R" \
  | bash ops/hooks/permission-hook.sh request | grep -c '"behavior":"deny"'
