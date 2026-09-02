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
# --- must DENY everywhere: the destroyers (v2.5) --------------------------------
# A worktree removed, pruned or moved by hand is another session's whole working state gone; a
# `git clean` in the shared checkout takes the gitignored .polaris/ with it; `rm -rf .polaris` is
# the same blast by another name; deleting an origin feat/<ID> pulls a live worktree's base out
# from under it; a kill that selects by NAME hits every session on this machine, not just yours.
git worktree remove .polaris/wt/T-001
git worktree remove --force /x/.polaris/wt/T-001
git worktree prune
git worktree move .polaris/wt/T-001 /tmp/x
git clean -fdx
git clean -f
git push origin --delete feat/T-001
git push -d origin feat/T-001
git push origin :refs/heads/feat/T-001
rm -rf .polaris
rm -r .polaris/wt/T-001
Remove-Item -Recurse -Force .polaris
taskkill /IM node.exe /F
Stop-Process -Name node
Get-Process node | Stop-Process
pkill -f uvicorn
killall node
kill -9 -1
npx kill-port 8001
fuser -k 8001/tcp
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
# you may always kill what you started and delete what is not .polaris: a pid-targeted kill, a
# dry-run clean and an ordinary push are never denied — that is what keeps this a tripwire.
git clean -n
git clean --dry-run
git push -u origin feat/T-001
rm -f .polaris/shots/T-001-a.png
rm -rf node_modules
kill 1234
kill -9 1234
taskkill /PID 1234 /F
Stop-Process -Id 1234
CASES
# the SAME mutating forms inside a task worktree are none of this hook's business — switching,
# resetting and stashing YOUR OWN checkout is the whole point of having one. The destroyers are the
# exception: there is no cwd where removing a worktree, deleting .polaris or killing by name is the
# right move, so those deny from here too (v2.5).
while IFS= read -r c; do
  [ -z "$c" ] && continue
  case "$c" in '#'*) continue;; esac
  printf 'wt:%s  %s\n' "$(bash "$H" --test "/x/.polaris/wt/T-000|$c")" "$c"
done <<'CASES'
git switch main
git reset --hard HEAD~1
git stash pop
git rebase main
git worktree remove .polaris/wt/T-000
rm -rf .polaris
pkill node
CASES
# the JSON layer itself: deny is hookSpecificOutput JSON on STDOUT (exit 0) — deliberately NOT
# ownership-guard's exit-2+stderr; the two hooks deny by different mechanisms, both correct as
# shipped (shared-checkout.md v2.1). The line below is the byte-exact decision Claude Code sees.
printf '{"cwd":"/tmp/fakerepo","tool_name":"Bash","tool_input":{"command":"git switch x"}}' | bash "$H"
# every pinned refusal lives ON ONE LINE in the hook itself — greppable by drills and role files.
# One emitter for all four: the message is a variable, so a new class costs a string, not a branch.
printf 'pinned-refusal-lines: %s\n' "$(grep -c 'the primary checkout is shared by every session' "$H")"
printf 'pinned-worktree-lines: %s\n' "$(grep -c 'a task worktree may be another session' "$H")"
printf 'pinned-push-lines: %s\n' "$(grep -c 'never delete origin refs by hand' "$H")"
printf 'pinned-kill-lines: %s\n' "$(grep -c 'never kill by name or kill the whole tree' "$H")"
printf 'json-deny-emitter-lines: %s\n' "$(grep -c 'permissionDecision' "$H")"
