# pytest-related — T-213 (ops/contracts/one-yes.md § 5): the pure python helpers in kit/ops/lib/surfaces.sh.
# pytest_related_files walks an awk import graph over tracked .py files and names the test files a
# change reaches; pytest_related_cmd rewrites ONLY the repo's own pytest segment of `test:`.
# T-214: related_cmds partitions the path list (.py + pytest config names -> python, the rest -> node),
# emits node commands first then pytest, all-or-nothing.
#
# HERMETIC: a throwaway repo under mktemp -d, sourced helpers, no pytest, no network, no live board.
KITDIR="$(pwd)/kit"; KIT="$KITDIR/ops/lib/surfaces.sh"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p pkg/sub tests lone
  : > pkg/__init__.py; : > pkg/sub/__init__.py
  echo 'X = 1' > pkg/a.py
  printf 'from . import a\n' > pkg/b.py
  printf 'from pkg.b import X\n' > tests/test_b.py
  printf 'import pkg.sub\nfrom pkg import (\n    a,\n    b as bee,\n)\n' > tests/c_test.py
  printf 'from .. import a\nimport os\n' > pkg/sub/deep.py
  printf 'import pkg.sub.deep\n' > tests/test_deep.py
  echo 'Y = 2' > lone/orphan.py
  echo 'import numpy' > lone/third.py
  mkdir -p web/node_modules/.bin
  printf '{"name":"web","scripts":{"test":"vitest run"}}
' > web/package.json
  : > web/node_modules/.bin/vitest; echo 'v1' > web/App.tsx; echo 'doc' > notes.md
  echo 'x' > conftest.py; echo '[pytest]' > pytest.ini; echo 'x' > requirements-dev.txt
  git add -A; git commit -qm init
) >/dev/null 2>&1
cd "$R"
PRIMARY="$R"; POLARIS_TAB="$(printf '\t')"
. "$KIT"
paths() { : > "$FIX/p"; for x in "$@"; do echo "$x" >> "$FIX/p"; done; }
sel() { # sel <label> <path>… — the selection and its rc
  local l="$1" o rc; shift; paths "$@"
  o="$(pytest_related_files "$FIX/p")"; rc=$?
  echo "== $l (rc $rc) =="; printf '%s\n' "$o"
}
sel chain pkg/a.py
sel one-hop pkg/b.py
sel relative-parent pkg/sub/deep.py
sel test-selects-itself tests/test_b.py
sel two-modules pkg/b.py pkg/sub/deep.py
sel conftest conftest.py
sel pytest-ini pytest.ini
sel requirements requirements-dev.txt
sel unreached lone/orphan.py
sel third-party lone/third.py
sel config-beats-reach pkg/a.py conftest.py
sel non-python docs/readme.md
cmdr() { # cmdr <label> <test-cmd> <file>…
  local l="$1" c="$2" o rc; shift 2
  o="$(pytest_related_cmd "$c" "$@")"; rc=$?
  echo "== $l (rc $rc) =="; printf '%s\n' "$o"
}
cmdr plain 'pytest tests -q' tests/test_b.py
cmdr repo-example 'PYTHONPATH=. backend/.venv/Scripts/python -m pytest backend/tests -q' backend/tests/test_b.py
cmdr compound 'npm run lint && pytest tests -q && echo done' tests/test_b.py tests/c_test.py
cmdr value-flags 'python -m pytest -k slow -n 4 tests --tb short -x' tests/test_b.py
cmdr no-path 'pytest -q -x' tests/test_b.py
cmdr two-paths 'pytest tests/a tests/b -q' tests/test_b.py
cmdr polaris-indirection 'bash ops/polaris doctor --fast' tests/test_b.py
cmdr no-pytest 'npm test' tests/test_b.py

# --- T-214: related_cmds — python, mixed node + python, all-or-nothing ---
cfg() { case "$1" in test) printf '%s
' "$TESTCMD";; *) printf '%s
' "${2:-}";; esac; }
rc_() { # rc_ <label> <test-cmd> <path>… — related_cmds' output and rc
  local l="$1" o rc; TESTCMD="$2"; shift 2; paths "$@"
  o="$(related_cmds "$FIX/p")"; rc=$?
  echo "== related $l (rc $rc) =="; printf '%s
' "$o"
}
rc_ py-only 'pytest tests -q' pkg/a.py
rc_ py-two 'pytest tests -q' pkg/b.py pkg/sub/deep.py
rc_ mixed 'pytest tests -q' web/App.tsx pkg/b.py
rc_ node-only 'pytest tests -q' web/App.tsx
rc_ py-unreached 'pytest tests -q' lone/orphan.py
rc_ mixed-py-unreached 'pytest tests -q' web/App.tsx lone/orphan.py
rc_ mixed-node-unqualified 'pytest tests -q' notes.md pkg/a.py
rc_ config-changed 'pytest tests -q' pytest.ini
rc_ not-parseable 'bash ops/polaris doctor --fast' pkg/a.py
rc_ no-pytest-segment 'npm test' pkg/a.py

# --- T-214: the CLI end to end (depth --commit, and qa on a DIRTY tree) with a python repo ---
CLI="$KITDIR/ops/polaris"
unset CLAUDE_CODE_SESSION_ID
mkpy() { # mkpy <name> — python repo, pytest test:, board initialised
  P="$FIX/$1"
  ( set -e
    git init -q -b main "$P" 2>/dev/null || { git init -q "$P"; git -C "$P" symbolic-ref HEAD refs/heads/main; }
    cd "$P"; git config user.email t@t; git config user.name t; git config core.autocrlf false
    mkdir -p pkg tests web/node_modules/.bin
    : > pkg/__init__.py; echo 'X = 1' > pkg/a.py; printf 'import pkg.a\n' > tests/test_a.py
    printf '{"name":"web","scripts":{"test":"vitest run"}}\n' > web/package.json
    printf '#!/bin/sh\necho FAKE\n' > web/node_modules/.bin/vitest; chmod +x web/node_modules/.bin/vitest
    echo v1 > web/App.tsx; printf 'node_modules/\n.polaris/\n' > .gitignore
    git add -A; git commit -qm init
    bash "$CLI" init-board
    printf 'test: true pytest tests -q\nlint: echo LINT\n' > ops/CONVENTIONS.md
    git add -A; git commit -qm board
    echo 'X = 2' > pkg/a.py; git commit -qam 'feat: pkg v2'
    echo v2 > web/App.tsx; echo 'X = 3' > pkg/a.py; git commit -qam 'feat: app and pkg v3'
  ) >/dev/null 2>&1
  cd "$P"
}
mkpy cli
echo "== depth --commit python =="; bash "$CLI" depth --commit "$(git rev-parse HEAD~1)" 2>&1
echo "== depth --commit mixed =="; bash "$CLI" depth --commit "$(git rev-parse HEAD)" 2>&1
# DIRTY tree + ancestor stamp + test_select UNSET: the whole suite still runs, timing still written
mkpy dirty
mkdir -p .polaris; printf '%s %s full\n' "$(git rev-parse HEAD~2)" "$(date +%s)" > .polaris/suite-stamp
echo '# dirty' >> ops/CONVENTIONS.md
OUT="$(bash "$CLI" qa 2>&1)"; RC=$?
read -r _ _ SC < .polaris/suite-stamp
echo "== dirty qa == rc=$RC scope=${SC:-none} suite-ran=$(printf '%s\n' "$OUT" | grep -cE '(test|lint) — green')"
if grep -qE '^[0-9]+ [0-9]+$' .polaris/last-suite-seconds 2>/dev/null; then echo "last-suite-seconds: ok"; else echo "last-suite-seconds: missing"; fi
