# checkout-guard is the repo's one DENY hook — the mirror of readonly-allow's only-ever-ALLOWS
# contract, in its own file on purpose. It refuses exactly one thing: a checkout-mutating git
# invocation issued from the PRIMARY checkout. --test skips the JSON layer and prints
# deny:<subcommand> or allow (mirroring readonly-allow.sh --test), so every verdict below is
# asserted in both directions, hermetically — no live board, no real repo. /tmp/fakerepo is NOT a
# git repo, and that is the point: the placement probe FAILS CLOSED (shared-checkout.md v2 field
# note — an unplaceable checkout-mutating command reads as primary), while a /.polaris/wt/ cwd
# segment is by itself proof of a task worktree. A new verb added to the parser MUST arrive with
# its case here, or it is not shipped.
H=kit/ops/hooks/checkout-guard.sh
while IFS= read -r c; do
  [ -z "$c" ] && continue
  case "$c" in '#'*) continue;; esac
  printf '%s  %s\n' "$(bash "$H" --test "/tmp/fakerepo|$c")" "$c"
done <<'CASES'
# --- must DENY in the primary: every checkout-mutating form --------------------
git switch main
git checkout feature-x
git checkout -- .
git reset --hard HEAD~1
git stash
git stash pop
git stash apply
git stash drop
git merge feature-x
git rebase main
git cherry-pick abc123
git worktree add /tmp/x
git branch -D topic
git branch -m old new
git fetch && git rebase origin/main
echo done; git switch -
env git switch main
/usr/bin/git checkout .
git -C . reset --hard
# --- must ALLOW in the primary: read-only git, the stash carve-out, non-git ----
# `git stash list` / `git stash show` are the ONLY read-only stash forms and readonly-allow's
# git_ok already allows both — denying them here would break the allow/deny disjointness the
# two-hook design rests on (v2.1 carve-out). A golden asserting all stash forms deny would fail
# against correct behavior.
git status
git log --oneline -5
git diff --stat
git stash list
git stash show
git stash list; git log -1
git branch -a
git branch --show-current
echo "git switch main"
grep -rn 'git switch' docs/
bash ops/polaris claim T-001
CASES
# the SAME mutating forms inside a task worktree are none of this hook's business
while IFS= read -r c; do
  [ -z "$c" ] && continue
  printf 'wt:%s  %s\n' "$(bash "$H" --test "/x/.polaris/wt/T-000|$c")" "$c"
done <<'CASES'
git switch main
git reset --hard HEAD~1
git stash pop
git rebase main
CASES
# the JSON layer itself: deny is hookSpecificOutput JSON on STDOUT (exit 0) — deliberately NOT
# ownership-guard's exit-2+stderr; the two hooks deny by different mechanisms, both correct as
# shipped (shared-checkout.md v2.1). The line below is the byte-exact decision Claude Code sees.
printf '{"cwd":"/tmp/fakerepo","tool_name":"Bash","tool_input":{"command":"git switch x"}}' | bash "$H"
# the pinned refusal lives ON ONE LINE in the hook itself — greppable by drills and role files
printf 'pinned-refusal-lines: %s\n' "$(grep -c 'the primary checkout is shared by every session' "$H")"
printf 'json-deny-emitter-lines: %s\n' "$(grep -c 'permissionDecision' "$H")"
