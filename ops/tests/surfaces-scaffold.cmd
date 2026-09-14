# `surfaces --scaffold` proposes a repo's test map from its own layout and `--scaffold --apply` is
# the SECOND sanctioned writer of a RULES-guarded file (ops/contracts/test-surfaces.md v2 § 14 ·
# § 16 · § 17). D6 is the whole reason this golden exists: an UNMAPPED surface runs the whole suite
# (safe); a MIS-mapped one silently skips real coverage while reporting green, and in a repo nobody
# is watching nobody would notice. So every byte the engine decides is pinned here — the runner it
# names, the rows it proposes, every pairing it skips and why, what --apply writes, what it refuses,
# and that a second run changes nothing. Two arithmetic facts come from the ENGINE's measured output,
# not the contract's worked examples (T-140): a test file under <dir>/__tests__/ is rule (a)'s
# pairing, never a co-located one (case 2 folds nothing), and an idempotent re-run counts the
# already-mapped rows as skips too (case 1's second run says 6, not 4).
#
# HERMETIC BY CONSTRUCTION (the adopt-stub pattern): one throwaway repo per fixture, each committing
# its own files — the engine's list is `git ls-files` — and the CLI run from INSIDE it: polaris
# anchors to the worktree-list primary, which becomes the fixture. The live board, the real map and
# the real CONVENTIONS never enter; running this twice from any board state is byte-identical.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mk() { # mk <name> — a throwaway repo on main; the caller adds files, `ci` commits them
  ( set -e
    git init -q -b main "$FIX/$1" 2>/dev/null || { git init -q "$FIX/$1"; git -C "$FIX/$1" symbolic-ref HEAD refs/heads/main; }
    cd "$FIX/$1"; git config user.email t@t; git config user.name t
  ) >/dev/null 2>&1
}
ci()   { ( cd "$FIX/$1" && git add -A && git commit -qm files ) >/dev/null 2>&1; }
S()    { ( cd "$FIX/$1" && shift && bash "$KIT" surfaces "$@" 2>&1 ); printf 'rc %s\n' "$?"; }
rows() { grep -v '^[[:space:]]*#' "$FIX/$1/ops/SURFACES.tsv" | grep -v '^[[:space:]]*$' || true; }
same() { if cmp -s "$1" "$2"; then echo "$3: byte-identical"; else echo "$3: CHANGED"; fi; }

# ---- 1. pytest — the whole path: propose, apply, health, idempotence, the stub, the live value,
#         the feat/* refusal. init-board seeds the header-only map; the fixture arms the seeded
#         RULES line the way INIT does (D2), so the health tail is the one a real repo prints.
mk py
( cd "$FIX/py"
  mkdir -p src/api src/db src/common lib/common tests/api tests/db tests/common
  printf '[tool.pytest.ini_options]\ntestpaths = ["tests"]\n' > pyproject.toml
  for f in src/api/x.py src/db/y.py src/util.py src/common/a.py lib/common/b.py \
           tests/api/test_x.py tests/db/test_y.py tests/test_util.py tests/common/test_a.py; do echo "# $f" > "$f"; done
  echo '# fixture' > README.md
  bash "$KIT" init-board
  sed 's|^#ops/SURFACES.tsv|ops/SURFACES.tsv|' ops/RULES.tsv > ops/RULES.tmp && mv ops/RULES.tmp ops/RULES.tsv
  printf 'voice: standard\ntest: pytest -q\n' > ops/CONVENTIONS.md
) >/dev/null 2>&1
ci py
cp -R "$FIX/py" "$FIX/pystub"; cp -R "$FIX/py" "$FIX/pylive"; cp -R "$FIX/py" "$FIX/pyfeat"   # fresh copies, pre-apply
cp "$FIX/py/ops/SURFACES.tsv" "$FIX/map0"; cp "$FIX/py/ops/CONVENTIONS.md" "$FIX/conv0"
echo '== 1a pytest --scaffold: the runner, four rows, two skips, and nothing written =='
S py --scaffold
same "$FIX/map0" "$FIX/py/ops/SURFACES.tsv" 'ops/SURFACES.tsv (still header-only)'
same "$FIX/conv0" "$FIX/py/ops/CONVENTIONS.md" 'ops/CONVENTIONS.md'
echo '== 1b --scaffold --apply: four [scaffold] rows, test_select: appended, nothing committed =='
S py --scaffold --apply
rows py
echo '-- ops/CONVENTIONS.md after --'
cat "$FIX/py/ops/CONVENTIONS.md"
echo '-- git status: written, not committed --'
( cd "$FIX/py" && git status --porcelain )
echo '== 1c surfaces: the written map is healthy =='
S py
echo '== 1d a second run proposes nothing and writes nothing =='
cp "$FIX/py/ops/SURFACES.tsv" "$FIX/map1"; cp "$FIX/py/ops/CONVENTIONS.md" "$FIX/conv1"
S py --scaffold --apply
same "$FIX/map1" "$FIX/py/ops/SURFACES.tsv" 'ops/SURFACES.tsv'
same "$FIX/conv1" "$FIX/py/ops/CONVENTIONS.md" 'ops/CONVENTIONS.md'
echo '== 1e a `# test_select:` stub is replaced in place, the prose after it stays put =='
printf '# test_select: x   # a stub adopt wrote\nprose the human wrote after it\n' >> "$FIX/pystub/ops/CONVENTIONS.md"
S pystub --scaffold --apply | tail -3
cat "$FIX/pystub/ops/CONVENTIONS.md"
echo '== 1f a live test_select: is the human'"'"'s: kept, and said =='
printf 'test_select: custom\n' >> "$FIX/pylive/ops/CONVENTIONS.md"
S pylive --scaffold --apply | tail -3
grep '^test_select:' "$FIX/pylive/ops/CONVENTIONS.md"
echo '== 1g on a feat/* branch --apply refuses: rc 1, nothing written =='
( cd "$FIX/pyfeat" && git checkout -q -b feat/T-X )
S pyfeat --scaffold --apply
same "$FIX/map0" "$FIX/pyfeat/ops/SURFACES.tsv" 'ops/SURFACES.tsv'
same "$FIX/conv0" "$FIX/pyfeat/ops/CONVENTIONS.md" 'ops/CONVENTIONS.md'

# ---- 2. jest — <dir>/__tests__/ pairs by rule (a), the co-located file by rule (c); nothing folds.
mk js
( cd "$FIX/js"; mkdir -p src/foo/__tests__ src/bar
  printf '{"scripts":{"test":"jest"}}\n' > package.json
  for f in src/foo/a.ts src/foo/__tests__/a.test.ts src/bar/b.ts src/bar/b.test.ts; do echo "// $f" > "$f"; done )
ci js
echo '== 2 jest: two rows, complete cmds, zero skips =='
S js --scaffold

# ---- 3. go — package paths only: the template is the whole suite, every row carries a complete cmd.
mk go
( cd "$FIX/go"; mkdir -p internal/foo cmd/app; printf 'module example.com/x\n\ngo 1.22\n' > go.mod
  for f in internal/foo/x.go internal/foo/x_test.go cmd/app/main.go; do echo 'package x' > "$f"; done )
ci go
echo '== 3 go: one row, template go test ./..., zero skips =='
S go --scaffold

# ---- 4. no runner — make filters by name, not path: NORUNNER names what it saw and nothing is written.
mk mk
( cd "$FIX/mk"; mkdir -p bin; printf 'test:\n\tbin/tool.sh\n' > Makefile; echo 'echo ok' > bin/tool.sh )
ci mk
echo '== 4a no runner: the NORUNNER note, rc 0 =='
S mk --scaffold
echo '== 4b --apply without ops/CONVENTIONS.md refuses =='
S mk --scaffold --apply
mkdir -p "$FIX/mk/ops"; printf 'test: make test\n' > "$FIX/mk/ops/CONVENTIONS.md"; cp "$FIX/mk/ops/CONVENTIONS.md" "$FIX/mkconv0"
echo '== 4c --apply with no runner writes nothing =='
S mk --scaffold --apply
if [ -e "$FIX/mk/ops/SURFACES.tsv" ]; then echo 'MAP WRITTEN'; else echo 'no ops/SURFACES.tsv written'; fi
same "$FIX/mkconv0" "$FIX/mk/ops/CONVENTIONS.md" 'ops/CONVENTIONS.md'

# ---- 5. breadth — a surface matching > 200 tracked paths is dropped, and said.
mk br
( cd "$FIX/br"; mkdir -p src/gen; printf '{"scripts":{"test":"vitest"}}\n' > package.json
  echo 'export const a = 1' > src/a.js; echo 'test("a", () => {})' > src/a.test.js
  i=1; while [ "$i" -le 250 ]; do echo "export const g$i = $i" > "src/gen/g$i.js"; i=$((i + 1)); done )
ci br
echo '== 5 breadth: src/ over 200 paths is skipped, nothing proposed =='
S br --scaffold
