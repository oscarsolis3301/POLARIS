# landed-content — `done` proves a task's files reached main before it lets go of the only copy
# (ops/contracts/safe-landing.md § 4-5, § 8, and v1.1 § E rider b).
#
# Four lanes once self-landed inside two minutes and three tasks reached done/ with their code missing
# from main: nothing compared main's files with the feat tip before `done` deleted the branch. Now done
# checks, re-lands only the paths that did not arrive (one [<ID>] commit through a wave + seal), checks
# again, and keeps the branch while anything is still missing. Five cases, one fixture:
#   a. a landed file clobbered on main → done re-lands it, ends green, the branch goes only after
#   b. unfixable (a hook rejects the path, so the re-land cannot commit) → ONE ⛔ line naming the task
#      and the file, rc 1, task still in review/, branch kept, lease free, primary back on main
#   c. the normal path → done prints what it always printed and makes no extra commit
#   d. a dirty tree + an ancestor suite stamp + test_select unset → the same, and nothing of it moves
#   e. kicked back AFTER its squash landed, fixed on the branch, handed off again → land still skips
#      by gate 1, done heals it with exactly ONE extra [T-5] commit
# The integrator lane is driven by hand (landing: integrator), so every case can reach between seal
# and done. HERMETIC: one throwaway repo under mktemp -d, no remote, no session id, HOME, USERPROFILE
# and POLARIS_AWAKE_HOME faked together, the CLI run from INSIDE the fixture. No sha, date or path.
unset CLAUDE_CODE_SESSION_ID POLARIS_INT_TOKEN
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home"
R="$FIX/repo"
IDS="T-1 T-2 T-3 T-4 T-5"
fof() { echo "src/$(echo "$1" | tr -d 'T-').txt"; }   # T-3 → src/3.txt
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src
  for id in $IDS; do echo x > "$(fof "$id")"; done
  echo clean > src/z.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  printf '# SPRINT 1 — landed content  capacity: 20\n' > ops/SPRINT.md
  for id in $IDS; do
    f="$(fof "$id")"
    printf -- '---\nid: %s\ntitle: lane %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - %s\nverify:\n  - grep -q y %s\n---\n## Why\nlane %s.\n' \
      "$id" "$id" "$f" "$f" "$id" > "ops/board/ready/$id.md"
  done
  git add -A; git commit -qm board
  mkdir -p .polaris
  printf '%s %s full\n' "$(git rev-parse HEAD)" "$(date +%s)" > .polaris/suite-stamp
) >/dev/null 2>&1
cd "$R"
col() { for c in backlog ready active review done blocked; do [ -f "ops/board/$c/$1.md" ] && { echo "$c"; return; }; done; echo none; }
yn() { if "$@"; then echo yes; else echo no; fi; }
same() { [ "$(git rev-parse -q --verify "main:$2" 2>/dev/null)" = "$(git rev-parse -q --verify "feat/$1:$2" 2>/dev/null)" ]; }
has_branch() { git rev-parse -q --verify "refs/heads/feat/$1" >/dev/null 2>&1; }
landed_n() { git log --format=%s main | grep -c "\[$1\]\$" || true; }
relandline() { git log --no-merges --fixed-strings --grep "[$1]" -1 --format=%B main | grep -c '^re-land: 1 path(s) did not arrive$' || true; }
quiet() { printf '1\n' > "$(git rev-parse --git-common-dir)/worktrees/$1/polaris-beat" 2>/dev/null || true; }
lane() { # claim → edit → handoff → land → seal, all quiet; the lane's file reads y on its branch
  f="$(fof "$1")"
  bash "$KIT" claim "$1" >/dev/null 2>&1
  ( cd "$R/.polaris/wt/$1" && echo y > "$f" && git commit -qam "feat: $1 the edit" && bash "$KIT" handoff "$1" ) >/dev/null 2>&1
  bash "$KIT" land "$1" >/dev/null 2>&1
  bash "$KIT" seal >/dev/null 2>&1
}

echo '== a. a landed file clobbered on main: done re-lands it =='
lane T-1
echo x > src/1.txt; git commit -qam 'chore: an unrelated edit puts the old text back'
quiet T-1
OUT="$(bash "$KIT" done T-1 2>&1)"; echo "done rc=$?"
printf '%s\n' "$OUT" | grep '^⚠ '
echo "T-1 is in: $(col T-1)"
echo "main has the feat text: $(yn grep -qx y src/1.txt)"
echo "[T-1] commits on main: $(landed_n T-1)"
echo "its re-land line: $(relandline T-1)"
echo "branch feat/T-1 left: $(yn has_branch T-1)"
echo "on: $(git rev-parse --abbrev-ref HEAD)"

echo '== c. the normal path: the same output, no extra commit =='
lane T-3
quiet T-3
N0="$(git rev-list --count main)"
bash "$KIT" done T-3 2>&1; echo "done rc=$?"
echo "extra commits: $(( $(git rev-list --count main) - N0 ))"
echo "T-3 is in: $(col T-3)"

echo '== d. a dirty tree, an ancestor suite stamp, test_select unset: the same again =='
lane T-4
echo dirt > src/z.txt
ST0="$(cat .polaris/suite-stamp)"
quiet T-4
N0="$(git rev-list --count main)"
bash "$KIT" done T-4 2>&1; echo "done rc=$?"
echo "extra commits: $(( $(git rev-list --count main) - N0 ))"
echo "T-4 is in: $(col T-4)"
echo "dirt still there: $(yn grep -qx dirt src/z.txt)"
echo "suite stamp untouched: $(yn [ "$(cat .polaris/suite-stamp)" = "$ST0" ])"
git checkout -q -- src/z.txt

echo '== e. kicked back after it landed, fixed, handed off again: done heals it =='
lane T-5
bash "$KIT" kickback T-5 -m 'one more fix' >/dev/null 2>&1
( cd "$R/.polaris/wt/T-5" && echo yy > src/5.txt && git commit -qam 'feat: T-5 the fix' && bash "$KIT" handoff T-5 ) >/dev/null 2>&1
echo "T-5 is in: $(col T-5)"
bash "$KIT" land T-5 2>&1 | grep '^✅'
quiet T-5
L0="$(landed_n T-5)"
OUT="$(bash "$KIT" done T-5 2>&1)"; echo "done rc=$?"
printf '%s\n' "$OUT" | grep '^⚠ '
echo "T-5 is in: $(col T-5)"
echo "main has the fix: $(yn grep -qx yy src/5.txt)"
echo "[T-5] commits on main: $(landed_n T-5)"
echo "[T-5] commits added by done: $(( $(landed_n T-5) - L0 ))"
echo "its re-land line: $(relandline T-5)"
echo "branch feat/T-5 left: $(yn has_branch T-5)"

echo '== b. unfixable: one line, rc 1, the branch and the task stay =='
lane T-2
echo x > src/2.txt; git commit -qam 'chore: an unrelated edit puts the old text back'
H="$(git rev-parse --git-path hooks)"; mkdir -p "$H"
printf '#!/bin/sh\ngit diff --cached --name-only | grep -qx src/2.txt && exit 1\nexit 0\n' > "$H/pre-commit"; chmod +x "$H/pre-commit"
quiet T-2
OUT="$(bash "$KIT" done T-2 2>&1)"; echo "done rc=$?"
printf '%s\n' "$OUT" | grep -E '^(⚠|⛔) '
echo "T-2 is in: $(col T-2)"
echo "branch feat/T-2 left: $(yn has_branch T-2)"
echo "[T-2] commits on main: $(landed_n T-2)"
echo "lease free: $(yn [ ! -d "$(git rev-parse --git-common-dir)/polaris-locks/.int-lease" ])"
echo "on: $(git rev-parse --abbrev-ref HEAD)"
echo "tree clean: $(yn [ -z "$(git status --porcelain --untracked-files=no)" ])"
