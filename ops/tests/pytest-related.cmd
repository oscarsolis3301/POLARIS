# pytest-related — T-213 (ops/contracts/one-yes.md § 5): the pure python helpers in kit/ops/lib/surfaces.sh.
# pytest_related_files walks an awk import graph over tracked .py files and names the test files a
# change reaches; pytest_related_cmd rewrites ONLY the repo's own pytest segment of `test:`.
# related_cmds does not call them yet (T-214).
#
# HERMETIC: a throwaway repo under mktemp -d, sourced helpers, no pytest, no network, no live board.
KIT="$(pwd)/kit/ops/lib/surfaces.sh"
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
