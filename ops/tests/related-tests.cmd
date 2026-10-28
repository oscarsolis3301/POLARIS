# related-tests — T-203 (ops/contracts/change-sized.md § 2-4): a change confined to a package whose
# test script is vitest/jest, with the runner installed, runs ONLY the tests the runner itself
# relates to the changed files (decided by test_select_for, shared by depth, qa and land --express).
# One stray path outside any package, a package with no runner installed, or `test_related: -`
# fall back to today's whole-suite behavior; a Python path never enters related mode.
#
# HERMETIC: a throwaway repo under mktemp -d, run from INSIDE it, with FAKE node_modules/.bin
# runners that only echo their argv into a log — no node, no network, no live board.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
LOG="$FIX/argv.log"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p app/src jlib/src nomod/src py tools
  printf '{"scripts":{"test":"vitest run"}}\n' > app/package.json
  printf '{"scripts":{"test":"jest --ci"}}\n'  > jlib/package.json
  printf '{"scripts":{"test":"vitest run"}}\n' > nomod/package.json
  mkdir -p app/node_modules/.bin jlib/node_modules/.bin
  printf '#!/bin/sh\necho "vitest $*" >> "%s"\n' "$LOG" > app/node_modules/.bin/vitest
  printf '#!/bin/sh\necho "jest $*" >> "%s"\n'   "$LOG" > jlib/node_modules/.bin/jest
  chmod +x app/node_modules/.bin/vitest jlib/node_modules/.bin/jest
  printf 'node_modules/\n' > .gitignore
  echo a > app/src/a.tsx; echo b > jlib/src/b.js; echo c > nomod/src/c.js
  echo p > py/mod.py; echo t > tools/x.dat; echo '[pytest]' > py/pytest.ini
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
: > "$LOG"
bash "$KIT" qa >/dev/null 2>&1          # a green baseline stamp, so every step below is a bounded change
step() { # step <label> <path>=<content> … — commit the change, show the verdict, then let qa run it
  local label="$1" item f v; shift
  for item in "$@"; do f="${item%%=*}"; v="${item#*=}"; mkdir -p "$(dirname "$f")"; printf '%s\n' "$v" > "$f"; done
  git add -A; git commit -qm "step $label"
  : > "$LOG"
  echo "== $label =="
  bash "$KIT" depth 2>&1
  bash "$KIT" qa >/dev/null 2>&1
  if [ -s "$LOG" ]; then sed 's/^/   ran: /' "$LOG"; else echo "   ran: nothing from a runner"; fi
}
step vitest-subpackage "app/src/a.tsx=a v2"
step jest-package "jlib/src/b.js=b v2"
step two-packages "app/src/a.tsx=a v3" "jlib/src/b.js=b v3"
step stray-path "app/src/a.tsx=a v4" "tools/x.dat=t v2"
step no-node-modules "nomod/src/c.js=c v2"
step python-path "py/mod.py=p v2"
printf 'test: true\ntest_related: -\n' > ops/CONVENTIONS.md; git add -A; git commit -qm off
bash "$KIT" qa >/dev/null 2>&1
step related-off "app/src/a.tsx=a v5"
