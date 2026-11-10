# landed-seal — `seal` checks the tasks it just merged, and `finish` will not call a run over while a
# done task's files are missing from main (ops/contracts/safe-landing.md § 6, § 7, v1.3 § J).
#
# Cases, one fixture, the integrator lane driven by hand (landing: integrator) so each can reach
# between land and seal:
#   a. a healthy seal prints what it always printed: no ⚠, no extra commit
#   b. a path clobbered on the wave before it seals → seal re-lands it in the same lease and says so
#   c. finish, task A landed and task B later changed the same file → no refusal (§ J: superseded)
#   d. finish, a landed task whose file was put back by a commit that is no task's → ONE ⛔ line
#   e. finish, a task in done/ with no landed commit on main at all → it is named with its paths
# The finish cases keep the branch by putting feat/<ID> back where it stood, the way a self-landed
# lane leaves it. HERMETIC: one throwaway repo under mktemp -d, no remote, no session id, HOME,
# USERPROFILE and POLARIS_AWAKE_HOME faked together, the CLI run from INSIDE it. No sha, date or path.
unset CLAUDE_CODE_SESSION_ID POLARIS_INT_TOKEN POLARIS_SEAL_NOCHECK
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home"
R="$FIX/repo"
task() { # task <ID> <file> — a ready task owning one file
  printf -- '---\nid: %s\ntitle: lane %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - %s\nverify:\n  - grep -q . %s\n---\n## Why\nlane %s.\n' \
    "$1" "$1" "$2" "$2" "$1" > "ops/board/ready/$1.md"
}
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src
  for i in 1 2 3 5 6; do echo x > "src/$i.txt"; done
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  printf '# SPRINT 1 — landed seal  capacity: 20\n' > ops/SPRINT.md
  for i in 1 2 3 5; do task "T-$i" "src/$i.txt"; done
  git add -A; git commit -qm board
  mkdir -p .polaris
  printf '%s %s full\n' "$(git rev-parse HEAD)" "$(date +%s)" > .polaris/suite-stamp
) >/dev/null 2>&1
cd "$R"
col() { for c in backlog ready active review done blocked; do [ -f "ops/board/$c/$1.md" ] && { echo "$c"; return; }; done; echo none; }
yn() { if "$@"; then echo yes; else echo no; fi; }
landed_n() { git log --format=%s main | grep -c "\[$1\]\$" || true; }
relandline() { git log --no-merges --fixed-strings --grep "[$1]" -1 --format=%B main | grep -c '^re-land: 1 path(s) did not arrive$' || true; }
quiet() { printf '1\n' > "$(git rev-parse --git-common-dir)/worktrees/$1/polaris-beat" 2>/dev/null || true; }
lease_free() { [ ! -d "$(git rev-parse --git-common-dir)/polaris-locks/.int-lease" ]; }
build() { # build <ID> <file> <text> — claim → edit → handoff → land, quiet; primary is left on the wave
  bash "$KIT" claim "$1" >/dev/null 2>&1
  ( cd "$R/.polaris/wt/$1" && echo "$3" > "$2" && git commit -qam "feat: $1 the edit" && bash "$KIT" handoff "$1" ) >/dev/null 2>&1
  bash "$KIT" land "$1" >/dev/null 2>&1
}
strip() { printf '%s\n' "$OUT" | tr -d '\r'; }
fin() { OUT="$(bash "$KIT" finish 2>&1)"; echo "finish rc=$?"; OUT="$(strip)"
  printf '%s\n' "$OUT" | grep -E '^⛔ T-[0-9]+ is done' || echo "(no done-task refusal)"
}

echo '== a. a healthy seal: nothing new =='
build T-1 src/1.txt y
OUT="$(bash "$KIT" seal 2>&1)"; echo "seal rc=$?"; OUT="$(strip)"
echo "warnings: $(printf '%s\n' "$OUT" | grep -c '^⚠' || true)"
echo "sealed line: $(printf '%s\n' "$OUT" | grep -c '^✅ sprint 1 sealed — ' || true)"
echo "[T-1] commits on main: $(landed_n T-1)"
echo "on: $(git rev-parse --abbrev-ref HEAD)"

echo '== b. a path clobbered on the wave before the seal: seal re-lands it =='
build T-2 src/2.txt y
echo "on the wave: $(git rev-parse --abbrev-ref HEAD | sed 's,^integrate/.*,integrate/<date>,')"
echo x > src/2.txt; git commit -qam 'chore: an unrelated edit puts the old text back'
OUT="$(bash "$KIT" seal 2>&1)"; echo "seal rc=$?"; OUT="$(strip)"
printf '%s\n' "$OUT" | grep '^⚠ '
echo "main has the feat text: $(yn grep -qx y src/2.txt)"
echo "[T-2] commits on main: $(landed_n T-2)"
echo "its re-land line: $(relandline T-2)"
echo "lease free: $(yn lease_free)"
echo "on: $(git rev-parse --abbrev-ref HEAD)"
for id in T-1 T-2; do quiet "$id"; bash "$KIT" done "$id" >/dev/null 2>&1; echo "$id is in: $(col "$id")"; done

echo '== c. finish: task A landed, task B later changed the same file =='
build T-3 src/3.txt y
bash "$KIT" seal >/dev/null 2>&1
TIP3="$(git rev-parse feat/T-3)"
quiet T-3; bash "$KIT" done T-3 >/dev/null 2>&1
git branch -f feat/T-3 "$TIP3"
task T-4 src/3.txt
build T-4 src/3.txt z
bash "$KIT" seal >/dev/null 2>&1
quiet T-4; bash "$KIT" done T-4 >/dev/null 2>&1
git branch -f feat/T-3 "$TIP3"
echo "T-3 and T-4 are in: $(col T-3) $(col T-4)"
echo "main has T-4's text: $(yn grep -qx z src/3.txt)"
fin

echo '== d. finish: a landed file put back by a commit that is no task =='
build T-5 src/5.txt y
bash "$KIT" seal >/dev/null 2>&1
TIP5="$(git rev-parse feat/T-5)"
quiet T-5; bash "$KIT" done T-5 >/dev/null 2>&1
echo x > src/5.txt; git commit -qam 'chore: an unrelated edit puts the old text back'
git branch -f feat/T-5 "$TIP5"
fin
echo "feat/T-5 still there: $(yn git show-ref -q --verify refs/heads/feat/T-5)"

echo '== e. finish: done on the board, never landed on main =='
git checkout -q -b feat/T-6 main
echo y > src/6.txt; git commit -qam 'feat: T-6 the edit'
git checkout -q main
printf -- '---\nid: T-6\ntitle: lane T-6\npoints: 1\nstatus: done\nfiles_owned:\n  - src/6.txt\n---\n' > ops/board/done/T-6.md
fin
