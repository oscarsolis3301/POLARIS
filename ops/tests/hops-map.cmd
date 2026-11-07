# hops-map: `polaris hops` — the layout report (ops/contracts/save-hops.md § 1.2-§ 1.5). A small shop
# sorted by KIND of file has one feature, the cart, scattered over components/, hooks/, services/ and
# tests/; hops must find it, name it, give it one home and list its MOVE rows. Beside the cart, in the
# same changes every time, sits one piece of bait per FIXED rule — a root file, a RULES path, both
# globs of a SURFACES row, a LAYOUT keep row, generated: and gallery:, public/, a framework-looking
# pages/, vendor/, a Unity Resources asset and its .meta, a dirty file and a file on an unmerged
# branch. Each changes with the cart often enough to join its cluster, so only the FIXED rules keep
# it out of every MOVE row: bait nothing would propose proves nothing.
# Also pinned: a two-hop rename chain (basketApi → bagApi → cartApi) counted under today's name, a
# change of more than 40 paths skipped, an import alone (weight 2) linking nothing, a two-folder
# cluster that is no SCATTER, two files that would land on one name dropped, a guide's STALE
# citations (and its non-citations), the too-small line, and every malformed call exiting 2.
#
# T-251 (§ 1.7) adds what decides whether a pass is worth it. MERGE: Header and Footer, two tiny
# files that always change together, are the shop's one — the cart's tiny files change together
# too, but a file a MOVE row already moves is never offered for a merge (one pass cannot move and
# merge a file: § 0.3 refuses that plan). --questions turns that MERGE and the framework-looking
# pages/ into the run's up-front questions; --facts prints what a guide is written from. A second
# repo, the monolith, pins every edge: SPLIT for a 600-line file pulling in 4 folders (599 lines,
# or 3 folders, is none) and for a folder of 41 files (40 is none); MERGE at exactly 75% of the
# changes (60% is none), at 40 lines (41 is none), the smaller folding into the larger, a tie by
# name, and never across two extensions or between a test and the code it tests; the question cap
# of 3; and the 15-line cap of --facts.
# T-264 (§ 12.6) adds --facts' `leave alone:` line — what a guide tells a reader never to move, and
# why — pinned on every piece of the shop's bait, then on one folder holding all six reasons.
#
# HERMETIC (the keys-drift pattern): a throwaway repo under mktemp -d. THE ENGINE TRAP (§ 8.4): the
# kit's code is reached as `POLARIS_ROOT=<fixture> python kit/ops/index.py hops`; the one call through
# the CLI entry exports POLARIS_INDEX_BIN at a wrapper, because the entry resolves the engine from the
# primary of the repo it runs in, and the fixture has none.
KIT="$(pwd)/kit/ops/polaris"
PY="$(pwd)/kit/ops/index.py"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/shop"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  printf '[core]\n\tautocrlf = false\n[user]\n\tname = Shop\n\temail = shop@shop.test\n' >> .git/config
  mkdir -p ops src/components src/hooks src/services src/utils src/legacy src/payments src/gen src/pages \
    public vendor Assets/Resources docs/shots tests tmp
  # one appended line per change, so every listed file really changes; package.json bumps instead
  v=0
  edit() { for f in "$@"; do printf '// %s\n' "$MSG" >> "$f"; done; }
  bump() { v=$((v + 1)); printf '{"name": "shop", "private": true, "version": "1.%s.0"}\n' "$v" > package.json; }
  BAIT='src/utils/money.ts tests/money.test.ts src/legacy/prices.ts src/payments/stripe.ts src/gen/cartSchema.ts
    docs/shots/cart.txt public/cart.svg src/pages/cart.tsx vendor/cartlib.js Assets/Resources/coin.asset
    Assets/Resources/coin.asset.meta'
  view() { printf 'import { useCart } from "../hooks/useCart";\nimport { cart } from "@/services/%s";\nexport function CartView() { return useCart() + cart(); }\n' "$1" > src/components/CartView.tsx
           printf 'import { cart } from "@/services/%s";\nimport { money } from "@/utils/format";\nexport function useCart() { return money(cart()); }\n' "$1" > src/hooks/useCart.ts; }

  # 1. The ground rules: root files and ops/ state, nothing movable.
  printf '.polaris/\n' > .gitignore
  bump
  printf '{"compilerOptions": {"baseUrl": ".", "paths": {"@/*": ["src/*"]}}}\n' > tsconfig.json
  printf 'base: main                # the shop ships from main\ngenerated: src/gen/\ngallery: docs/shots\n' > ops/CONVENTIONS.md
  printf '# scope\tkind\tpattern\tmessage\nsrc/legacy/\tpath\t-\tthe old price table is frozen\n' > ops/RULES.tsv
  printf '# surface\ttests\tcmd\tnote\nsrc/utils/money.ts\ttests/money.test.ts\t-\tthe money maths\n' > ops/SURFACES.tsv
  printf '# path\tverdict\twhy — the layout record; polaris hops never proposes a keep row\nsrc/payments/stripe.ts\tkeep\tframework convention\n' > ops/LAYOUT.tsv
  git add -A; git commit -qm 'shop: the ground rules'

  # 2. The screens and the http client. Header imports format: a change together + an import = 3.
  printf 'import { money } from "@/utils/format";\nexport function Header() { return money(0); }\n' > src/components/Header.tsx
  for c in Footer Button Menu; do printf 'export function %s() { return "%s"; }\n' "$c" "$c" > "src/components/$c.tsx"; done
  printf '# Hooks — shared state for the screens\n' > src/hooks/README.md
  printf 'export function money(cents: number) { return (cents / 100).toFixed(2); }\n' > src/utils/format.ts
  printf 'export async function get(url: string) { return url; }\n' > src/services/http.ts
  git add -A; git commit -qm 'ui: header, footer, button, menu and the http client'

  # 3. The cart, and every piece of bait with it. useCart imports format but never changes with it:
  #    an import alone weighs 2 and must link nothing.
  MSG='cart: the basket, its badge and the price maths'
  view basketApi
  printf 'export function CartBadge() { return 0; }\n' > src/components/CartBadge.tsx
  printf 'export function useCartTotal() { return 0; }\n' > src/hooks/useCartTotal.ts
  printf 'export * from "./useCart";\n' > src/hooks/index.ts
  printf 'import { get } from "./http";\nexport function cart() { return get("/cart"); }\n' > src/services/basketApi.ts
  printf 'import { useCart } from "../src/hooks/useCart";\ntest("cart", () => useCart());\n' > tests/cart.test.ts
  edit $BAIT; bump
  git add -A; git commit -qm "$MSG"

  # 4. Sign-in (a two-folder cluster: never a SCATTER) and a guide for services/.
  printf 'import { get } from "./http";\nexport function signIn() { return get("/auth"); }\n' > src/services/authApi.ts
  printf 'import { signIn } from "../src/services/authApi";\ntest("auth", () => signIn());\n' > tests/auth.test.ts
  printf '%s\n' '# notes the owner keeps' '<!-- polaris:guide -->' '' \
    '# src/services/ — every call the shop makes to its API' \
    'Start with `cartApi.ts`; the screens reach it through `src/hooks/useCart.ts`.' \
    'The old `basketApi.ts` and `src/old/` are gone. Shared maths: `src/utils/` and `../utils/format.ts`.' \
    'Not paths: `npm test` · `https://shop.test/api` · `*.ts` · `-v` · `$API_URL` · `<id>` · `README`.' \
    '<!-- /polaris:guide -->' 'Below the block it is the owner'"'"'s again: `nowhere.ts` is never checked.' > src/services/CLAUDE.md
  git add -A; git commit -qm 'auth: sign in, and a guide for services'

  # 5-8. The cart grows: renamed twice (basketApi → bagApi → cartApi) and changed with all its bait.
  git mv src/services/basketApi.ts src/services/bagApi.ts
  view bagApi; printf 'export * from "./bagApi";\n' > src/services/index.ts
  git add -A; git commit -qm 'cart: call it the bag API, exported from services'
  MSG='cart: coupons'
  edit src/components/CartView.tsx src/components/CartBadge.tsx src/hooks/useCart.ts src/hooks/useCartTotal.ts \
    src/services/bagApi.ts tests/cart.test.ts $BAIT; bump
  git commit -qam "$MSG"
  git mv src/services/bagApi.ts src/services/cartApi.ts
  view cartApi; printf 'export * from "./cartApi";\n' > src/services/index.ts
  git commit -qam 'cart: call it cartApi'
  MSG='cart: tax on the receipt'
  edit src/components/CartView.tsx src/components/CartBadge.tsx src/hooks/useCart.ts src/hooks/useCartTotal.ts \
    src/hooks/index.ts src/services/cartApi.ts tests/cart.test.ts $BAIT; bump
  git commit -qam "$MSG"

  # 9-10. A 45-path drop and its 41-path removal: skipped (> 40), so Button and Menu never pair up.
  MSG='chore: a generated drop'
  edit src/components/Header.tsx src/components/Footer.tsx src/components/Button.tsx src/components/Menu.tsx
  for i in 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41; do
    printf 'drop %s\n' "$i" > "tmp/f$i.txt"; done
  git add -A; git commit -qm "$MSG"
  git rm -rq tmp; git commit -qm 'chore: drop the generated files'

  # 11-12. Header and Footer change together twice more: a one-folder cluster, no SCATTER either.
  MSG='ui: a tighter header and footer'; edit src/components/Header.tsx src/components/Footer.tsx; git commit -qam "$MSG"
  MSG='ui: footer links in the header'; edit src/components/Header.tsx src/components/Footer.tsx; git commit -qam "$MSG"

  # In flight: useCartTotal changes on an unmerged branch, CartBadge is half-edited in the tree.
  git checkout -qb feat/wip
  MSG='cart: a running total'; edit src/hooks/useCartTotal.ts; git commit -qam "$MSG"
  git checkout -q main
  printf '// half-done\n' >> src/components/CartBadge.tsx
) >/dev/null 2>&1
H() { ( POLARIS_ROOT="$1" python "$PY" hops "${@:2}" 2>&1 ); printf 'rc=%s\n' "$?"; }

# 1. The screen: the score line, MAP largest first (a guide's purpose, then a README heading, else -),
#    the cart SCATTER with its home under src/, Footer folding into Header (4+5 lines, together in
#    all 3 of their changes — the 45-path drop does not count), the folder of 5+ files with no
#    guide, the STALE citations, the next line — 2.89 = 26 folders over the 9 changes that touch a
#    movable file.
H "$R" | tr -d '\r'

# 2. --tsv: every row, nothing capped — and the MOVE rows hold the cart and nothing else: the two
#    index.ts files would both land on src/cart/index.ts, so neither moves. CartView, useCart and
#    cartApi change together in all 5 of their changes and are tiny, yet no MERGE names them: their
#    MOVE rows come first.
TSV="$(H "$R" --tsv | tr -d '\r')"
printf '%s\n' "$TSV"

# 3. No MOVE row ever names a FIXED path, as a from or a to.
printf '%s\n' "$TSV" | awk -F'\t' -v bait="package.json src/utils/money.ts tests/money.test.ts src/legacy/prices.ts src/payments/stripe.ts src/gen/cartSchema.ts docs/shots/cart.txt public/cart.svg src/pages/cart.tsx vendor/cartlib.js Assets/Resources/coin.asset Assets/Resources/coin.asset.meta src/hooks/useCartTotal.ts src/components/CartBadge.tsx" \
  'BEGIN { n = split(bait, b, " "); for (i = 1; i <= n; i++) fixed[b[i]] = 1 }
   $1 == "MOVE" { moves++; if (($2 in fixed) || ($3 in fixed)) bad++ }
   END { printf "MOVE rows: %d · naming a FIXED path: %d\n", moves, bad + 0 }'

# 4. --stale: only the STALE rows (rc 0) — cheap, no history read.
H "$R" --stale | tr -d '\r'

# 5. The same rows through the CLI entry's fast path (find|show|hops → index_fast → the engine).
printf '#!/usr/bin/env bash\nexec python "%s" "$@"\n' "$PY" > "$FIX/engine"; chmod +x "$FIX/engine"
( cd "$R" && POLARIS_INDEX_BIN="$FIX/engine" bash "$KIT" hops --stale 2>&1 | tr -d '\r' ); printf 'entry rc=%s\n' "$?"

# 6. A plan that is not there, --facts with no folder or one that is no folder of tracked files, a
#    flag given an argument it takes none of, and anything else: ONE usage line on stderr, rc 2,
#    never a traceback.
for a in '--score p.tsv' '--owned p.tsv' '--proof p.tsv' '--remap p.tsv' --facts '--facts src/nowhere' \
         '--facts ../src' '--facts src a' '--due --tsv' '--questions x' --bogus '--tsv --stale'; do
  err="$( POLARIS_ROOT="$R" python "$PY" hops $a 2>&1 >/dev/null )"; rc=$?
  err="${err//$'\r'/}"
  printf '%s: rc=%s · %s line(s) · %s\n' "$a" "$rc" "$(printf '%s\n' "$err" | grep -c .)" "${err%%]*}]"
done

# 7. Under 20 tracked files: the one too-small line, rc 0; --tsv prints no row; --stale finds none,
#    rc 1; --questions has nothing to ask, rc 1.
T="$FIX/tiny"
( git init -q "$T" && cd "$T" && printf 'a\n' > a.txt && printf 'b\n' > b.txt && git add -A \
  && git -c user.name=t -c user.email=t@t commit -qm tiny ) >/dev/null 2>&1
H "$T" | tr -d '\r'
H "$T" --tsv | tr -d '\r'
H "$T" --stale | tr -d '\r'
H "$T" --questions | tr -d '\r'

# 8. --questions: the MERGE first, then the framework-looking src/pages/ — app/, pages/ or routes/
#    with no framework config at the root, held by that rule alone (public/ is routed outright, so
#    nobody is asked about it). Each with its safe answer first and as the default. A next.config.js
#    at the root says pages/ IS routed: that question goes, the merge stays.
H "$R" --questions | tr -d '\r'
( cd "$R" && printf 'module.exports = {};\n' > next.config.js && git add next.config.js ) >/dev/null 2>&1
H "$R" --questions | tr -d '\r'
( cd "$R" && git rm -q --cached next.config.js && rm -f next.config.js ) >/dev/null 2>&1

# 9. --facts src/services: the 15 lines its guide is written from — the guide's purpose, the files
#    most imported (cartApi: two screens and the barrel), its symbols in find's ranking, the folders
#    that change with it, the test importing it, one line per file.
H "$R" --facts src/services | tr -d '\r'

# 9b. The same flag where a pass uses it — a tidy task's worktree, the cart moved (git mv, committed;
#     no importer fixed yet, so nothing imports the new paths). POLARIS_ROOT names the tree, so the
#     facts describe the layout AFTER the moves: src/cart/, a folder main does not have (asked of
#     the primary it is rc 2), its files' past followed through the renames — the history is the
#     worktree's HEAD, not main — so the cart's bait folders still show as changing with it.
WT="$R/.polaris/wt/T-9"
( cd "$R" && git worktree add -q "$WT" -b feat/T-9 && cd "$WT" && mkdir -p src/cart \
  && git mv src/components/CartView.tsx src/hooks/useCart.ts src/services/cartApi.ts tests/cart.test.ts src/cart/ \
  && git commit -qm 'layout: the cart in one folder' ) >/dev/null 2>&1
H "$WT" --facts src/cart | tr -d '\r'
H "$R" --facts src/cart | tr -d '\r' | sed -n '$p'

# 9c. --facts' `leave alone:` line (§ 12.6), right after `tests:`: the folder's files FIXED for good,
#     each with the FIRST reason that holds it, in this order — generated · vendored · guarded ·
#     test map · kept · public. Every piece of the shop's bait is asked about where it sits (and a
#     published package joins it, the one reason the shop had no bait for): each lasting reason is
#     named; a framework folder, a Unity asset and work in flight are no reason a guide should
#     give, so they are not. Then src/mixed/ holds all six, named so that A-Z would put them the
#     other way round: the reasons' order wins, four are named and the other two counted.
( cd "$R" && mkdir -p packages/coins src/mixed \
  && printf '{"name": "coins", "version": "1.0.0", "main": "index.js"}\n' > packages/coins/package.json \
  && printf 'export const coins = 1;\n' > packages/coins/index.js \
  && for f in zones.gen.ts yaml.min.js xrates.ts wallet.ts vault.ts units.go tokens.asmdef notes.ts; do
       printf '// %s\n' "$f" > "src/mixed/$f"; done \
  && printf 'base: main                # the shop ships from main\ngenerated: src/gen/ src/mixed/*.gen.ts\ngallery: docs/shots\n' > ops/CONVENTIONS.md \
  && printf 'src/mixed/xrates.ts\tpath\t-\tthe exchange rates are signed off\n' >> ops/RULES.tsv \
  && printf 'src/mixed/wallet.ts\ttests/money.test.ts\t-\tthe wallet maths\n' >> ops/SURFACES.tsv \
  && printf 'src/mixed/vault.ts\tkeep\tframework convention\n' >> ops/LAYOUT.tsv \
  && git add -A ) >/dev/null 2>&1
for d in src/gen docs/shots vendor src/legacy src/utils tests src/payments packages/coins public Assets/Resources src/hooks; do
  printf '%s/ · %s\n' "$d" "$( POLARIS_ROOT="$R" python "$PY" hops --facts "$d" 2>&1 | tr -d '\r' | grep '^leave alone:' )"
done
H "$R" --facts src/mixed | tr -d '\r'

# 10. The monolith: every edge of MERGE and SPLIT, in a repo whose history ONE fast-import stream
#     writes (no fork per commit). The files live in shell variables (b_<path, every other char _>);
#     each change appends one line to every file it lists, so a file's lines = what it started with
#     + the changes that touched it. The first change lists all 110 files: over 40 paths, skipped.
M="$FIX/mono"
( git init -q -b main "$M" 2>/dev/null || { git init -q "$M"; git -C "$M" symbolic-ref HEAD refs/heads/main; }
  printf '[core]\n\tautocrlf = false\n' >> "$M/.git/config"
  NL=$'\n'; n=0; ALL=''
  # put <path> <first line> [<more lines>] — a file to be, listed for the first change
  put() { k="b_${1//[^A-Za-z0-9]/_}"; v="$2$NL"; j=0
          while [ "$j" -lt "${3:-0}" ]; do j=$((j + 1)); v="$v// more $j$NL"; done
          printf -v "$k" '%s' "$v"; ALL="$ALL $1"; }
  # fc <message> <path>... — one change: every path it lists gains the line `// change <n>`
  fc() { n=$((n + 1))
         printf 'commit refs/heads/main\ncommitter Mono <mono@mono.test> %s +0000\ndata <<EOF\n%s\nEOF\n' "$((1700000000 + n * 60))" "$1"
         shift
         for p in "$@"; do k="b_${p//[^A-Za-z0-9]/_}"; printf -v "$k" '%s// change %s\n' "${!k}" "$n"
           printf 'M 100644 inline %s\ndata <<EOF\n%sEOF\n' "$p" "${!k}"; done; printf '\n'; }
  i=0; while [ "$i" -lt 41 ]; do i=$((i + 1)); put "src/flat/f$i.ts" "export const f$i = $i;"; done
  i=0; while [ "$i" -lt 40 ]; do i=$((i + 1)); put "src/full/g$i.ts" "export const g$i = $i;"; done
  # SPLIT: engine 597+3 = 600 lines (split), near 596+3 = 599 (not); three 697+3 = 700 lines but it
  # pulls in only 3 folders twice (src/e once) — not. util (its own folder) and main (one above it)
  # change with engine every time and never count.
  put src/core/engine.ts 'export function run() { return 1; }' 596
  put src/core/near.ts 'export function near() { return 1; }' 595
  put src/core/three.ts 'export function three() { return 1; }' 696
  for p in src/core/util.ts src/main.ts src/a/x.ts src/b/x.ts src/c/x.ts src/d/x.ts src/e/x.ts \
           src/a/y.ts src/b/y.ts src/c/y.ts src/e/y.ts web/pages/home.tsx; do put "$p" 'export const v = 1;'; done
  # MERGE, one pair per run of changes so no two pairs ever meet: k+l together 4× · b+a 3 of a's 4
  # (exactly 75%) and b the smaller · c+d 3 of 5 (60%) · e (37+1+3 = 41 lines) + f · g.ts + g.css ·
  # h.ts + its test · i + j the same size.
  put src/bits/a.ts 'export const a = 1;' 2; put src/bits/e.ts 'export const e = 1;' 36
  for x in b c d f i j k; do put "src/bits/$x.ts" "export const $x = 1;"; done
  put src/bits/l.ts 'export const l = 1;' 2; put src/bits/g.ts 'export const g = 1;'
  put src/bits/g.css '.g { color: red; }'; put src/bits/h.ts 'export function h() { return 1; }'
  put src/bits/h.test.ts "import { h } from \"./h\";${NL}test(\"h\", () => h());"
  { fc 'mono: everything at once' $ALL
    S='src/core/engine.ts src/core/near.ts src/core/util.ts src/main.ts src/a/x.ts src/b/x.ts src/c/x.ts src/d/x.ts'
    fc 'core: run faster' $S src/e/x.ts; fc 'core: run safer' $S
    fc 'core: three ways' src/core/three.ts src/a/y.ts src/b/y.ts src/c/y.ts src/e/y.ts
    fc 'core: three more' src/core/three.ts src/a/y.ts src/b/y.ts src/c/y.ts
    for c in 1 2 3 4; do fc "bits: k and l $c" src/bits/k.ts src/bits/l.ts; done
    for c in 1 2 3; do fc "bits: a and b $c" src/bits/a.ts src/bits/b.ts; done; fc 'bits: a alone' src/bits/a.ts
    for c in 1 2 3; do fc "bits: c and d $c" src/bits/c.ts src/bits/d.ts; done
    fc 'bits: c alone' src/bits/c.ts; fc 'bits: d alone' src/bits/d.ts
    for c in 1 2 3; do fc "bits: e and f $c" src/bits/e.ts src/bits/f.ts; done
    for c in 1 2 3; do fc "bits: g and its style $c" src/bits/g.ts src/bits/g.css; done
    for c in 1 2 3; do fc "bits: h and its test $c" src/bits/h.ts src/bits/h.test.ts; done
    for c in 1 2 3; do fc "bits: i and j $c" src/bits/i.ts src/bits/j.ts; done
    printf 'done\n'; } | git -C "$M" fast-import --quiet --done
  git -C "$M" reset -q --hard ) >/dev/null 2>&1

# 10a. The screen: three MERGE rows (k+l first — together most), then SPLIT for engine.ts and src/flat/.
H "$M" | tr -d '\r'
# 10b. The same rows in --tsv: a file's SPLIT carries its lines and folders, a folder's its files and -.
H "$M" --tsv | tr -d '\r' | awk '/^(MERGE|SPLIT)\t|^rc=/'
# 10c. Four things to ask — three merges and web/pages/ — and the round holds at most 3.
H "$M" --questions | tr -d '\r'
# 10d. --facts on a folder of 14 files: six label lines, then 9 file lines — 15, never more. Nothing
#      outside src/bits/ ever changed with it, so `changes with` says `-`, and nothing in it is held
#      for good, so neither does `leave alone`.
H "$M" --facts src/bits | tr -d '\r'
