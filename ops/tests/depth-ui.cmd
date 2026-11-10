# depth-ui — T-291 (ops/contracts/test-depth.md § v2.2, § v2.3, § v2.5): a small UI change gets the
# depth `ui` (lint + typecheck + a look, no suite) only when EVERY changed path left after test_skip and
# test_look is a test_ui file AND every task is 1-2 points (or carries test_depth: ui) with risk: normal.
# Anything else must keep today's verdict, byte for byte — so each "today's verdict" case below is
# pinned beside the case that does qualify, and differs from it in one thing only.
#
# HERMETIC: a throwaway repo under mktemp -d with the kit INSTALLED in it, so every command runs the
# fixture's own ops/polaris (and one run of the source kit must agree with it). HOME, USERPROFILE and
# POLARIS_AWAKE_HOME are faked together. No sha, path or time printed.
KIT_DIR="$(pwd)/kit"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"; mkdir -p "$HOME"
unset POLARIS_SHA POLARIS_UPDATE_HINTS POLARIS_ROOT
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p web src docs
  echo 'v1' > web/App.tsx; echo 'v1' > web/app.css; echo 'v1' > src/x.py; echo 'doc v1' > docs/readme.md
  printf '.polaris/\n' > .gitignore
  git add -A; git commit -qm init
  bash "$KIT_DIR/ops/install.sh" "$R"
  bash ops/polaris init-board
  printf 'test: echo TEST\nlint: echo LINT\ntypecheck: echo TC\nbuild: echo BUILD\nuat: echo UAT\ntest_related: -\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
) >/dev/null 2>&1
cd "$R"
echo "installed: $([ -f ops/polaris ] && echo yes || echo no)"

task() { # task <ID> <points> <risk> <test_depth|-> — writes the board task file (not git-tracked)
  local id="$1" pts="$2" risk="$3" td="$4" extra=""
  [ "$td" != "-" ] && extra="test_depth: $td
"
  printf -- '---\nid: %s\ntitle: fixture %s\ntype: feature\npoints: %s\nwsjf: 1\nrisk: %s\n%sowner: null\nbranch: null\nstatus: active\nfiles_owned:\n  - web/App.tsx\nverify: []\n---\n' \
    "$id" "$id" "$pts" "$risk" "$extra" > "ops/board/active/$id.md"
}
mkbranch() { # mkbranch <ID> <path>=<content> [<path>=<content> …] — a feat/<ID> branch off main
  local id="$1" item f v; shift
  ( git checkout -q -b "feat/$id" main
    for item in "$@"; do
      f="${item%%=*}"; v="${item#*=}"
      mkdir -p "$(dirname "$f")"; printf '%s\n' "$v" > "$f"
    done
    git add -A; git commit -qm "feat: $id fixture"
    git checkout -q main
  ) >/dev/null 2>&1
}
D() { printf 'depth %s\n' "$*"; bash ops/polaris depth "$@" 2>&1; printf 'rc %s\n' "$?"; }

echo '== a 1-point risk: normal task changing one .tsx =='
mkbranch T-1 "web/App.tsx=v2"; task T-1 1 normal -; D T-1
echo '== the source kit agrees with the installed one =='
[ "$(bash ops/polaris depth T-1 2>&1)" = "$(bash "$KIT_DIR/ops/polaris" depth T-1 2>&1)" ] && echo agrees || echo DISAGREES
echo '== 2 points, .tsx beside a .css and a docs file: the look and docs paths drop, one ui path left =='
mkbranch T-2 "web/App.tsx=v3" "web/app.css=v3" "docs/readme.md=doc v3"; task T-2 2 normal -; D T-2
echo '== the same .tsx in a 3-point task: today'"'"'s verdict =='
mkbranch T-3 "web/App.tsx=v4"; task T-3 3 normal -; D T-3
echo '== 3 points + test_depth: ui: ui, and the why names the task =='
mkbranch T-4 "web/App.tsx=v5"; task T-4 3 normal ui; D T-4
echo '== .tsx beside a .py: today'"'"'s verdict =='
mkbranch T-5 "web/App.tsx=v6" "src/x.py=v6"; task T-5 1 normal -; D T-5
echo '== risk: high: today'"'"'s verdict (and test_depth: ui cannot lift it) =='
mkbranch T-6 "web/App.tsx=v7"; task T-6 1 high ui; D T-6
echo '== .css alone: look, unchanged =='
mkbranch T-7 "web/app.css=v8"; task T-7 1 normal -; D T-7
echo '== depth --commit at ui: lint and typecheck would run; test, build and uat would be skipped =='
( echo 'v9' > web/App.tsx && git commit -qam 'ui: a tighter header [T-1]' ) >/dev/null 2>&1
bash ops/polaris depth --commit HEAD 2>&1; echo "rc $?"
echo '== no taskfile (a commit with no task): today'"'"'s verdict =='
( echo 'v10' > web/App.tsx && git commit -qam 'ui: a tighter footer' ) >/dev/null 2>&1
bash ops/polaris depth --commit HEAD 2>&1; echo "rc $?"
echo '== qa says the depth line at ui with no suite time, even when one was measured =='
mkdir -p .polaris; echo '1500 1' > .polaris/last-suite-seconds
echo "$(git rev-parse HEAD) 1 full" > .polaris/suite-stamp
( echo 'v11' > web/App.tsx && git commit -qam 'ui: a softer button [T-1]' ) >/dev/null 2>&1
bash ops/polaris qa 2>&1 | grep 'depth:'
echo "== test_ui: - : the 1-point .tsx change of T-1 goes back to today's verdict =="
printf 'test_ui: -\n' >> ops/CONVENTIONS.md
D T-1
