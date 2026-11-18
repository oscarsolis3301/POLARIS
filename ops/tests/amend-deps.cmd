# amend-deps — `amend <ID> --deps +<ID>|-<ID> -m "why"` ends hand-edited depends_on
# (ops/contracts/smooth.md § 4). Pinned: every refusal writes nothing (the board ref does not move);
# a `+` on a ready card waiting on unfinished work moves it to backlog/ in the same commit; a `-`
# never promotes; a `+` on a finished dependency leaves a ready card ready; an active card can be
# amended; ONE board commit per amendment, its Notes line and its event.
# HERMETIC: one throwaway repo under mktemp -d, no remote, no session id, HOME, USERPROFILE and
# POLARIS_AWAKE_HOME faked together, the CLI run from INSIDE it. No sha, date or path printed.
unset CLAUDE_CODE_SESSION_ID POLARIS_INT_TOKEN
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home"
R="$FIX/repo"
task() { # task <column> <ID> <deps> — a card owning one file of its own
  printf -- '---\nid: %s\ntitle: card %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: %s\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/%s.txt\ndepends_on: %s\nverify:\n  - grep -q . src/%s.txt\n---\n## Why\ncard %s.\n' \
    "$2" "$2" "$1" "$2" "$3" "$2" "$2" > "ops/board/$1/$2.md"
}
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/seed.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  printf '# SPRINT 1 — amend deps  capacity: 20\n' > ops/SPRINT.md
  task ready T-1 '[]'
  task backlog T-2 '[T-1]'
  task ready T-3 '[]'
  task review T-4 '[]'
  task done T-5 '[]'
  task ready T-6 '[]'
  task active T-7 '[]'
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
col() { for c in backlog ready active review done blocked; do [ -f "ops/board/$c/$1.md" ] && { echo "$c"; return; }; done; echo none; }
deps() { grep '^depends_on:' "ops/board/$(col "$1")/$1.md"; }
ref() { git rev-parse -q --verify refs/heads/polaris/board 2>/dev/null || echo none; }
try() { # try <args…> — one amend; prints its last line, its rc and whether the board ref moved
  local before after out rc
  before="$(ref)"
  out="$(bash "$KIT" amend "$@" 2>&1)"; rc=$?
  after="$(ref)"
  printf '%s\n' "$out" | tr -d '\r' | grep -E '^(⛔|✅)' | sed 's/ (usage: .*//'
  if [ "$before" = "$after" ]; then echo "   rc=$rc · board untouched"; else echo "   rc=$rc · board moved: $(git log -1 --format=%s polaris/board)"; fi
}

echo '== refusals write nothing'
git worktree add -q -b feat/T-7 "$FIX/wt" main >/dev/null 2>&1
( cd "$FIX/wt" && bash "$KIT" amend T-7 --deps +T-5 -m "why" ) 2>&1 | tr -d '\r'
try T-3 --deps +T-2
try T-3 --deps +T-2 --verify 1 -m "why" -- true
try T-4 --deps +T-2 -m "why"
try T-42 --deps +T-2 -m "why"
try T-3 --deps +T-99 -m "why"
try T-3 --deps +T-3 -m "why"
try T-2 --deps +T-1 -m "why"
try T-3 --deps -T-1 -m "why"
try T-1 --deps +T-2 -m "why"

echo '== + on a ready card, the dependency unfinished — it waits in backlog/'
try T-3 --deps +T-2 -m "it needs the second card first"
echo "T-3 is in: $(col T-3) · $(deps T-3)"
grep '^- amend: deps' "ops/board/$(col T-3)/T-3.md"
echo "amend events for T-3: $(grep -c '"ev":"amend","id":"T-3"' ops/board/EVENTS.ndjson)"

echo '== - never promotes'
try T-3 --deps -T-2 -m "not needed after all"
echo "T-3 is in: $(col T-3) · $(deps T-3)"

echo '== + a finished dependency — a ready card stays ready'
try T-6 --deps +T-5 -m "uses the fifth card"
echo "T-6 is in: $(col T-6) · $(deps T-6)"

echo '== an active card'
try T-7 --deps +T-1 -m "found mid-build"
echo "T-7 is in: $(col T-7) · $(deps T-7)"
