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
# citations (and its non-citations), the too-small line, and the flags later tasks own exiting 2.
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
#    the cart SCATTER with its home under src/, the folder of 5+ files with no guide, the STALE
#    citations, the next line — 2.89 = 26 folders over the 9 changes that touch a movable file.
H "$R" | tr -d '\r'

# 2. --tsv: every row, nothing capped — and the MOVE rows hold the cart and nothing else: the two
#    index.ts files would both land on src/cart/index.ts, so neither moves.
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

# 6. The flags later tasks own, and anything else: ONE usage line on stderr, rc 2, never a traceback.
for a in '--score p.tsv' '--owned p.tsv' '--proof p.tsv' '--remap p.tsv' --due '--facts src' --questions --bogus '--tsv --stale'; do
  err="$( POLARIS_ROOT="$R" python "$PY" hops $a 2>&1 >/dev/null )"; rc=$?
  err="${err//$'\r'/}"
  printf '%s: rc=%s · %s line(s) · %s\n' "$a" "$rc" "$(printf '%s\n' "$err" | grep -c .)" "${err%%]*}]"
done

# 7. Under 20 tracked files: the one too-small line, rc 0; --tsv prints no row; --stale finds none, rc 1.
T="$FIX/tiny"
( git init -q "$T" && cd "$T" && printf 'a\n' > a.txt && printf 'b\n' > b.txt && git add -A \
  && git -c user.name=t -c user.email=t@t commit -qm tiny ) >/dev/null 2>&1
H "$T" | tr -d '\r'
H "$T" --tsv | tr -d '\r'
H "$T" --stale | tr -d '\r'
