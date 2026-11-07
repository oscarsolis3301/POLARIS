# seal-fallback — a seal that refuses strands nothing (ops/contracts/save-hops.md § 15, T-259).
#
# Closing a wave used to leave a mess behind in three small ways, and each one is pinned here on a
# real `seal` or a real `handoff`:
#   1) a wave begun before midnight and closed after it: `seal` with no date looked only for today's
#      wave, and the self-landing tail never types a date. Now the ONE open wave is sealed, said first;
#   2) two waves open: picking one would be a guess, so `seal` names both, oldest first, moving nothing;
#   3) 4) the two refusals after the branch check — no readable sprint number, a reused one — put the
#      checkout back on main before they stop, instead of leaving it sitting on the wave;
#   5) under landing: self with no sprint line, the handoff no longer lands onto a wave that could never
#      close: the task waits in review/, ONE line says what to add, and the handoff stays green.
#
# HERMETIC (the where-done / pr-one-link pattern): ONE throwaway repo under mktemp -d, no remote, the
# CLI run from INSIDE it so polaris anchors to the fixture as its primary. Cases 1-4 build each wave by
# hand — integrate/<date> cut from main, one commit whose subject ends in [<ID>] (the record a seal
# bullets), and the checkout left ON it, exactly where `land` leaves it — so only case 5 claims and
# hands off for real. The waves are dated 2001-…, a day no run will ever call today; today itself
# prints as <today>. A refusal is a line on stderr, so every call folds 2>&1 into what is pinned.
# ops/SPRINT.md is board state (disk only, ignored on main): the sprint line is written, rewritten and
# removed in place, never committed.
# RUNTIME ~35-42s (measured, Windows/Git Bash): two real seals at ~8s each, one claim + handoff at ~12s.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export POLARIS_AWAKE_HOME="$FIX/awake-home"   # never the real ~/.claude/polaris
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/seed.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: self\n' > ops/CONVENTIONS.md
  printf '# MAP — fixture\n\n## Entry points\n| Path | What it is |\n|---|---|\n| `src/` | the code |\n' > ops/MAP.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
TODAY="$(date +%F)"
Q() { sed "s#$TODAY#<today>#g"; }
# H <n> <goal>: the sprint line · W <date> <ID>: a wave begun on <date>, the checkout left on it
H() { printf '# SPRINT %s — %s  capacity: 5\n' "$1" "$2" > ops/SPRINT.md; }
W() { { git checkout -q -b "integrate/$1" main && echo "$2" > "src/$2.txt" && git add -- "src/$2.txt" \
        && git commit -q -m "feat: $2 lands on the $1 wave [$2]" -- "src/$2.txt"; } >/dev/null 2>&1; }
# S [<date>]: the real seal, every line it prints (stdout and stderr), then its exit code
S() { ( bash "$KIT" seal "$@" 2>&1; echo "rc=$?" ) | Q; }
on() { echo "checkout on: $(git rev-parse --abbrev-ref HEAD)"; }
moved() { [ "$(git rev-parse main)" = "$1" ] && echo 'main unmoved: yes' || echo 'main unmoved: NO'; }

echo '== 1. a wave begun on an earlier day: seal with no date takes the one open wave, and says so first =='
H 1 'midnight waves'
W 2001-01-01 T-1
out="$(S)"
printf '%s\n' "$out" | sed -n 1p
printf '%s\n' "$out" | grep -E '^(rc=|✅ sprint )'
echo "main is now: $(git log -1 --format=%s main)"
git merge-base --is-ancestor integrate/2001-01-01 main && echo 'the wave is inside main: yes' || echo 'the wave is inside main: NO'
[ "$(git rev-parse -q --verify refs/tags/sprint/1)" = "$(git rev-parse main)" ] && echo 'sprint/1 tags main: yes' || echo 'sprint/1 tags main: NO'
on

echo '== 2. two waves open: seal with no date names both, oldest first, and nothing moves =='
git checkout -q main
W 2001-01-03 T-3
git checkout -q main
W 2001-01-02 T-2
b="$(git rev-parse main)"
S
moved "$b"
# an explicit date is untouched by any of this: it seals that wave (the tag's move is printed as two
# short commit ids, masked), and the 2001-01-03 wave stays open for the cases below
S 2001-01-02 | grep -E '^(rc=|✅ sprint )' | sed -E 's/[0-9a-f]{7,40} → [0-9a-f]{7,40}$/<old> → <new>/'

echo '== 3. no sprint line, the checkout on the wave: the refusal puts it back on main, then stops =='
rm -f ops/SPRINT.md
git checkout -q integrate/2001-01-03
b="$(git rev-parse main)"
S
moved "$b"
on

echo '== 4. a reused sprint number, the checkout on the wave: the same, by its date =='
# sprint/2 already names a commit from unrelated history — a parentless one stands in for it
H 2 'a number used before'
git tag sprint/2 "$(git commit-tree -m 'foreign history' 'main^{tree}' </dev/null)"
git checkout -q integrate/2001-01-03
b="$(git rev-parse main)"
S 2001-01-03
moved "$b"
on

echo '== 5. landing: self with no sprint line: the handoff stays green, lands nothing, says what to add =='
rm -f ops/SPRINT.md
printf -- '---\nid: T-5\ntitle: a task with nowhere to land\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/T-5.txt\nverify: []\n---\n' > ops/board/ready/T-5.md
bash "$KIT" claim T-5 >/dev/null 2>&1
out="$( cd .polaris/wt/T-5 && echo five > src/T-5.txt && git add -A && git commit -qm 'feat: T-5 five' && bash "$KIT" handoff T-5 2>&1 )"; rc=$?
printf '%s\n' "$out" | Q
echo "handoff rc=$rc"
echo "the ⚠ line, times printed: $(printf '%s\n' "$out" | grep -cF '⚠ T-5 waits in review/')"
echo "T-5 sits in: $(ls ops/board/*/T-5.md | sed 's#^ops/board/##; s#/T-5\.md$##')"
n=0; for w in $(git for-each-ref --format='%(refname)' refs/heads/integrate/); do
  n=$((n + $(git log --format=%s "$w" | grep -c '\[T-5\]$'))); done
echo "[T-5] commits on any integrate/*: $n"
on
