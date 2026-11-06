# guide-stale: a folder guide that cites a path which no longer exists gets NOTICED, and nothing is
# ever blocked by it (ops/contracts/save-hops.md § 6, T-249). Two advisories, one rule for what a
# citation is — `hops --stale`'s: drift prints one line per stale citation, never counted and never
# red under --strict; verify and handoff warn the task that removes a path a guide it does NOT own
# still cites, read off the TASK's worktree (where the path is already gone), never the primary
# (where it still exists). A task that owns the guide gets no warning: fixing it is its own job.
#
# HERMETIC (the drift-deps / pack-visual pattern): ONE throwaway repo under mktemp -d with its own
# board, tasks and guides, the CLI run from INSIDE it so polaris anchors to the fixture as PRIMARY.
# THE ENGINE TRAP (§ 8.4): a bash caller resolves the engine from the fixture's own primary, which has
# no ops/index.py, so POLARIS_INDEX_BIN points at a wrapper that execs the KIT's index.py. A second
# wrapper ends every line with CR, the way the INSTALLED index.py writes on Windows until the dogfood.
# `landing: integrator` is load-bearing: the passing handoff stops in review/ and never lands.
# RUNTIME ~35s (measured, Windows/Git Bash): a dozen real CLI runs after the setup, two claims among them.
KIT="$(pwd)/kit/ops/polaris"
PY="$(pwd)/kit/ops/index.py"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export POLARIS_AWAKE_HOME="$FIX/awake-home"   # never the real ~/.claude/polaris
printf '#!/usr/bin/env bash\nexec python "%s" "$@"\n' "$PY" > "$FIX/engine"; chmod +x "$FIX/engine"
cat > "$FIX/engine-crlf" <<'EOF'
#!/usr/bin/env bash
"$(dirname "$0")/engine" "$@" | awk '{ printf "%s\r\n", $0 }'
exit "${PIPESTATUS[0]}"
EOF
chmod +x "$FIX/engine-crlf"
export POLARIS_INDEX_BIN="$FIX/engine"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  mkdir -p src/pricing src/cart src/old docs
  for f in src/pricing/pricing.ts src/pricing/tax.ts src/cart/cart.ts src/cart/coupon.ts src/old/a.ts src/old/b.ts; do
    printf 'export const x = 1;\n' > "$f"; done
  # The pricing guide cites the cart three ways: from the root, again from the root (one citation,
  # however often it is written), and climbing out of its own folder — all three name ONE path. It
  # also cites a folder, files beside it, and `rates.ts`, which was gone before any task began.
  printf '%s\n' '# the owner'"'"'s notes, above the block' '<!-- polaris:guide -->' \
    '# src/pricing/ — prices, tax and the totals a customer sees' \
    'Start with `pricing.ts`; tax rules live in `tax.ts`. The old `rates.ts` was retired.' \
    'Totals come from `src/cart/cart.ts` (see `src/cart/cart.ts` again, or `../cart/cart.ts`).' \
    'The old helpers sit in `src/old/`.' \
    '<!-- /polaris:guide -->' > src/pricing/CLAUDE.md
  printf '%s\n' '<!-- polaris:guide -->' '# docs/ — how the shop works, for people' \
    'The checkout walk-through follows `src/cart/cart.ts`; the old one, `checkout.md`, is gone.' \
    'Coupons: `src/cart/coupon.ts`. The old helpers, kept for history: `src/old`.' \
    '<!-- /polaris:guide -->' > docs/CLAUDE.md
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  # T-1 retires the cart: removes cart.ts and the old helpers, MOVES the coupons to a new top-level
  # attic/, and owns no guide. T-2 removes the tax rules and owns the pricing guide that cites them.
  T() { printf -- '---\nid: %s\ntitle: %s\ntype: feature\npoints: 1\nwsjf: %s\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n%sverify: []\n---\n' \
        "$1" "$2" "$3" "$(printf '%s\n' "$4" | sed 's/^/  - /')
" > "ops/board/ready/$1.md"; }
  T T-1 'retire the cart' 5 'src/cart/cart.ts
src/cart/coupon.ts
src/old/
attic/coupon.ts'
  T T-2 'drop the tax rules' 4 'src/pricing/tax.ts
src/pricing/CLAUDE.md'
) >/dev/null 2>&1
W1="$R/.polaris/wt/T-1"; W2="$R/.polaris/wt/T-2"
# The one machine-specific byte any of this could emit is the mktemp path; nothing pinned below
# carries one today (every line names a repo-relative path), so N() is a guard, not a rewrite.
N() { sed -e 's#[^ ]*tmp\.[A-Za-z0-9][A-Za-z0-9]*#<fix>#g'; }
D() { ( cd "$R" && bash "$KIT" drift "$@" 2>/dev/null ) | N; }
V() { out="$( cd "$1" && bash "$KIT" verify 2>&1 )"; rc=$?; printf '%s\n' "$out" | N; printf 'rc %s\n' "$rc"; }
C() { ( cd "$R/ops/board"
  printf 'active:'; for f in active/*.md; do [ -e "$f" ] && printf ' %s' "${f#active/}"; done; printf '\n'
  printf 'review:'; for f in review/*.md; do [ -e "$f" ] && printf ' %s' "${f#review/}"; done; printf '\n' ); }
# SAME <lf output> <crlf output>: byte-equal, or the CR run shown with every CR made visible.
SAME() { if [ "$1" = "$2" ]; then echo 'same bytes as the LF engine: yes'; else echo 'same bytes as the LF engine: NO'
  printf '%s\n' "$2" | awk '{ gsub(/\r/, "<CR>"); print }'; fi; }

echo '== 1. drift: one advisory per stale citation — printed, never counted, never red =='
# Guides in sorted order, citations in the order they are written. The verdict stays "board clean"
# and --strict stays rc 0: the speed.md § 3 advisory class, because a stale guide must never stop a run.
D1="$(D)"; printf '%s\n' "$D1"
( cd "$R" && bash "$KIT" drift --strict >/dev/null 2>&1 ); echo "strict-rc=$?"

echo '== 2. an engine that ends its lines with CR changes nothing =='
SAME "$D1" "$( export POLARIS_INDEX_BIN="$FIX/engine-crlf"; D )"

echo '== 3. no python engine: drift says nothing about guides at all =='
( cd "$R" && POLARIS_INDEX_BIN='' POLARIS_INDEX_TEST_NOPY=1 bash "$KIT" drift 2>/dev/null ) | N

echo '== 4. hops: off — drift prints exactly what it printed before guides were checked =='
cp "$R/ops/CONVENTIONS.md" "$FIX/conv"
printf 'base: main\nlanding: integrator\nhops: off\n' > "$R/ops/CONVENTIONS.md"
D
cp "$FIX/conv" "$R/ops/CONVENTIONS.md"

echo '== 5. T-1 removes and moves paths two guides cite; with no engine its verify says nothing of it =='
( cd "$R" && bash "$KIT" claim T-1 ) >/dev/null 2>&1
( cd "$W1" && git config user.email t@t && git config user.name t && git rm -rq src/cart/cart.ts src/old \
  && mkdir -p attic && git mv src/cart/coupon.ts attic/coupon.ts && git commit -qm 'retire the cart' ) >/dev/null 2>&1
out="$( cd "$W1" && POLARIS_INDEX_BIN='' POLARIS_INDEX_TEST_NOPY=1 bash "$KIT" verify 2>&1 )"; rc=$?
printf '%s\n' "$out" | N; echo "rc $rc"

echo '== 6. with the engine, verify warns once per guide and path — and still returns 0 =='
# The cart is written three times in the pricing guide (twice from the root, once climbing out with
# ../) and once in docs: one warning per guide, never four. A MOVED path is a removed one (the coupons
# went to attic/). A folder cited with or without its trailing / names the folder the task emptied.
# rates.ts and checkout.md were stale before T-1 and are not its doing: drift reports those, and this
# warning never does.
V6="$(V "$W1")"; printf '%s\n' "$V6"

echo '== 7. the same verify through a CR engine: the same bytes =='
SAME "$V6" "$( export POLARIS_INDEX_BIN="$FIX/engine-crlf"; V "$W1" )"

echo '== 8. handoff warns the same, right after the map hint, and hands off: rc 0, review/ =='
out="$( cd "$W1" && bash "$KIT" handoff 2>&1 )"; rc=$?; printf '%s\n' "$out" | N; echo "rc $rc"
C

echo '== 9. T-2 owns the guide that cites what it removes: the guide IS stale there, and no warning =='
( cd "$R" && bash "$KIT" claim T-2 ) >/dev/null 2>&1
( cd "$W2" && git config user.email t@t && git config user.name t && git rm -q src/pricing/tax.ts \
  && git commit -qm 'drop the tax rules' ) >/dev/null 2>&1
( POLARIS_ROOT="$W2" python "$PY" hops --stale 2>&1 ) | tr -d '\r' | N
V "$W2"
