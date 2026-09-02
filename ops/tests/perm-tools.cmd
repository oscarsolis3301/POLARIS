# Auto mode must not stop a POLARIS session on a click the kit can pre-authorize. Every other rule
# the kit ships is a Bash(...)/PowerShell(...) PREFIX, so none of them can cover the harness's own
# tools — which is why five parallel sessions each stalled on the same "proceed with EnterWorktree?"
# prompt. The fix is data, in two places, and both are pinned here: kit/.claude/settings.json is
# what a fresh install writes into the repo, bootstrap.py's PERMS is what arm_machine unions into
# ~/.claude/settings.json. Drift in either one brings the prompt back for half the world.
#
# A name counts only as a bare quoted string. `Bash(Task ...)` is a prefix rule for a command that
# happens to share the name and is NOT the same permission, so the quotes are load-bearing here.
#
# This golden reds in BOTH directions on purpose. Lose a name and the count falls. ADD one of the
# two human gates — the plan approval and the question — and line 3 stops being 0: those two clicks
# are the ones POLARIS keeps forever, and an allow rule for either must never land quietly.
# Line 4 watches the set-if-absent merges that carry the names to a real machine: no code change was
# needed for that, and this is how we find out if someone rewrites one. See
# ops/contracts/permission-rules.md.
S=kit/.claude/settings.json
B=kit/ops/bootstrap.py
for pair in "settings.json|$S" "bootstrap.py PERMS|$B"; do
  label=${pair%%|*}; file=${pair#*|}; found=""; n=0
  for name in EnterWorktree ExitWorktree Workflow Task Agent TodoWrite SendMessage; do
    grep -q "\"$name\"" "$file" && { found="$found $name"; n=$((n+1)); }
  done
  printf '%s:%s → %s of 7\n' "$label" "$found" "$n"
done
printf 'gates absent (ExitPlanMode AskUserQuestion): settings.json %s · bootstrap.py %s\n' \
  "$(( $(grep -c 'ExitPlanMode' "$S") + $(grep -c 'AskUserQuestion' "$S") ))" \
  "$(( $(grep -c 'ExitPlanMode' "$B") + $(grep -c 'AskUserQuestion' "$B") ))"
printf 'union blocks intact: bootstrap.py %s · admin.sh %s\n' \
  "$(grep -c 'added = \[rule for rule in PERMS' "$B")" \
  "$(grep -c 'for rule in rules:' kit/ops/lib/admin.sh)"
