# hops-moves: the four checks on a plan of moves — `polaris hops --score | --owned | --proof | --remap`
# — and FIXED rule 9, published code never proposed (ops/contracts/save-hops.md § 1.4 rule 9, § 1.6).
# A small shop sorted by KIND of file has its cart scattered over components/, hooks/, services/ and
# tests/, and its game coin over three Unity folders. Every cart change also touches one piece of
# PUBLISHED bait per rule-9 clause — a package.json with "main" (its manifest, its entry and the file
# the entry imports), a pyproject [project] package and the module [project.scripts] names, a Java, a
# Go and a Kotlin file — so only rule 9 keeps them out of the cart's MOVE rows; and the coin file that
# sits in its own .asmdef never moves out of it, while its two neighbours do (rule 9 d).
# --proof is the guarantee, so it is shown failing as often as passing: the cart moved the way a tidy
# step does it (git mv, importers fixed — an @/ alias, a relative import re-aimed, a doc's mention —
# a guide, the root map and LAYOUT.tsv written beside it) proves green from a task worktree reading
# the plan in the PRIMARY's .polaris/; one logic edit, a Java `package` line, an unplanned deletion,
# a missing destination and a merge that drops a line each prove red; a dotted python import and a
# clean merge prove green; and once the step lands on main the same plan still proves green — the
# integrator re-runs verify lines there.
#
# HERMETIC (the keys-drift pattern): a throwaway repo under mktemp -d. THE ENGINE TRAP (§ 8.4): the
# kit's code is reached as `POLARIS_ROOT=<fixture> python kit/ops/index.py hops …`, never through a
# primary's installed ops/index.py. Edits go through a temp file: `sed -i` differs on macOS.
PY="$(pwd)/kit/ops/index.py"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/shop"
WT="$R/.polaris/wt/T-1"
rw() { f="$1"; shift; sed "$@" "$f" > "$f.rw" && mv "$f.rw" "$f"; }
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  printf '[core]\n\tautocrlf = false\n[user]\n\tname = Shop\n\temail = shop@shop.test\n' >> .git/config
  mkdir -p ops src/components src/hooks src/services src/utils tests docs packages/ui-kit shopkit tools \
    scripts java/src/shop go/cart kotlin/cart Assets/Scripts/UI Assets/Scripts/Data Assets/Scripts/Net
  # one appended comment per change, so every listed file really changes; the ui-kit manifest bumps
  v=0
  edit() { for f in "$@"; do case "$f" in *.py) c='#' ;; *) c='//' ;; esac; printf '%s %s\n' "$c" "$MSG" >> "$f"; done; }
  bump() { v=$((v + 1)); printf '{"name": "ui-kit", "version": "1.%s.0", "main": "index.js"}\n' "$v" > packages/ui-kit/package.json; }
  BAIT='packages/ui-kit/index.js packages/ui-kit/button.js shopkit/__init__.py shopkit/cart_prices.py
    tools/cartcli.py java/src/shop/Money.java go/cart/total.go kotlin/cart/CartPrice.kt'
  CART='src/components/CartView.tsx src/hooks/useCart.ts src/services/cartApi.ts tests/cart.test.ts'
  meta() { printf 'fileFormatVersion: 2\nguid: %s\n' "$2" > "$1.meta"; }

  # 1. The ground rules: root files, nothing movable. The root CLAUDE.md ends with POLARIS's block.
  printf '.polaris/\n' > .gitignore
  printf '{"name": "shop", "private": true}\n' > package.json
  printf '{"compilerOptions": {"baseUrl": ".", "paths": {"@/*": ["src/*"]}}}\n' > tsconfig.json
  printf '[project]\nname = "shopkit"\n\n[project.scripts]\ncart-report = "tools.cartcli:main"\n' > pyproject.toml
  printf '# Shop\n<!-- POLARIS:END -->\n' > CLAUDE.md
  printf 'base: main\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm 'shop: the ground rules'

  # 2. What the cart leans on — and the published bait, the python tools, the coin's network assembly.
  printf 'export function get(url: string) { return url; }\n' > src/services/http.ts
  printf '# Cart\n\nThe calls live in `services/cartApi`; the screen is `components/CartView`.\n' > docs/cart.md
  bump
  printf 'export { Button } from "./button.js";\n' > packages/ui-kit/index.js
  printf 'export function Button(label) { return label; }\n' > packages/ui-kit/button.js
  printf '# shopkit: the prices other repos import\n' > shopkit/__init__.py
  printf 'def cart_price(total):\n    return total * 0.9\n' > shopkit/cart_prices.py
  printf 'def main():\n    print("cart")\n' > tools/cartcli.py
  printf 'def build():\n    return "report"\n' > scripts/cart_report.py
  printf 'import scripts.cart_report\nfrom scripts.cart_report import build\n\n\ndef run():\n    return scripts.cart_report.build() + build()\n' > scripts/nightly.py
  printf 'package shop;\n\npublic final class Money {\n    public long cents;\n}\n' > java/src/shop/Money.java
  printf 'package cart\n\nfunc Total(c int) int { return c }\n' > go/cart/total.go
  printf 'package cart\n\nfun cartPrice(c: Int) = c\n' > kotlin/cart/CartPrice.kt
  printf 'export function round2(x: number) {\n  return Math.round(x * 100) / 100;\n}\n' > src/utils/round.ts
  printf 'import { round2 } from "./round";\n\nexport function money(x: number) {\n  return round2(x).toFixed(2);\n}\n' > src/utils/money.ts
  printf '{"name": "Net"}\n' > Assets/Scripts/Net/Net.asmdef; meta Assets/Scripts/Net/Net.asmdef 00000000000000000000000000000001
  git add -A; git commit -qm 'shop: the http client, the published kits, the python tools'

  # 3-5. The cart, three times, every bait file changing with it.
  printf 'import { useCart } from "@/hooks/useCart";\nimport { Button } from "../../packages/ui-kit/index.js";\nexport function CartView() { return Button(useCart()); }\n' > src/components/CartView.tsx
  printf 'import { fetchCart } from "@/services/cartApi";\nexport function useCart() { return fetchCart(); }\n' > src/hooks/useCart.ts
  printf 'import { get } from "./http";\nexport function fetchCart() { return get("/cart"); }\nexport const percentOff = (total: number) => total * 0.9;\n' > src/services/cartApi.ts
  printf 'import { fetchCart } from "@/services/cartApi";\ntest("cart", () => fetchCart());\n' > tests/cart.test.ts
  MSG='cart: the cart'; edit $BAIT; bump
  git add -A; git commit -qm "$MSG"
  MSG='cart: coupons'; edit $CART $BAIT; bump; git commit -qam "$MSG"
  MSG='cart: tax'; edit $CART $BAIT; bump; git commit -qam "$MSG"

  # 6. The app shell imports the cart screen through @/ — an importer, never part of the cart itself.
  printf 'import { CartView } from "@/components/CartView";\nexport const App = () => CartView();\n' > src/App.tsx
  git add -A; git commit -qm 'shop: the app shell'

  # 7-9. The coin, three times, across three Unity folders; CoinSync sits in the Net assembly.
  printf 'using UnityEngine;\n\npublic class CoinView : MonoBehaviour { }\n' > Assets/Scripts/UI/CoinView.cs
  printf 'public class CoinData { public int Count; }\n' > Assets/Scripts/Data/CoinData.cs
  printf 'public class CoinSync { }\n' > Assets/Scripts/Net/CoinSync.cs
  meta Assets/Scripts/UI/CoinView.cs 00000000000000000000000000000002
  meta Assets/Scripts/Data/CoinData.cs 00000000000000000000000000000003
  meta Assets/Scripts/Net/CoinSync.cs 00000000000000000000000000000004
  git add -A; git commit -qm 'coin: the coin'
  COIN='Assets/Scripts/UI/CoinView.cs Assets/Scripts/Data/CoinData.cs Assets/Scripts/Net/CoinSync.cs'
  MSG='coin: sync the count'; edit $COIN; git commit -qam "$MSG"
  MSG='coin: show the count'; edit $COIN; git commit -qam "$MSG"
) >/dev/null 2>&1
H() { ( POLARIS_ROOT="$R" python "$PY" hops "$@" 2>&1 ); printf 'rc=%s\n' "$?"; }

# 1. --tsv: the cart is ONE scatter of four files; no published file joined it, and no published
#    folder is even on the MAP (scripts/ is: a pyproject freezes packages, not every .py). MOVE rows
#    for the cart and two of the three coin files — CoinSync.cs is in the coin's cluster, but moving
#    it would take it out of the Net assembly, so it gets no MOVE row.
TSV="$(H --tsv | tr -d '\r')"
printf '%s\n' "$TSV"
printf '%s\n' "$TSV" | awk -F'\t' -v pub="package.json packages/ui-kit/package.json packages/ui-kit/index.js packages/ui-kit/button.js shopkit/__init__.py shopkit/cart_prices.py tools/cartcli.py java/src/shop/Money.java go/cart/total.go kotlin/cart/CartPrice.kt" \
  'BEGIN { n = split(pub, b, " "); for (i = 1; i <= n; i++) P[b[i]] = 1 }
   $1 == "MOVE" { moves++; if (($2 in P) || ($3 in P)) pm++; if ($2 == "Assets/Scripts/Net/CoinSync.cs") am++; if ($2 ~ /\.meta$/) mm++ }
   $1 == "SCATTER" { n = split($5, f, ","); for (i = 1; i <= n; i++) if (f[i] in P) ps++ }
   END { printf "MOVE rows: %d · naming published code: %d · leaving its assembly: %d · a .meta: %d · published code in a SCATTER: %d\n", moves, pm + 0, am + 0, mm + 0, ps + 0 }'

# 2. The plan = every MOVE row, in the primary's .polaris/ where a tidy pass keeps it.
mkdir -p "$R/.polaris"
printf '%s\n' "$TSV" | awk -F'\t' '$1 == "MOVE" { print "move\t" $2 "\t" $3 }' > "$R/.polaris/hops-plan.tsv"

# 3. --score: the history with every from renamed to its to — fewer folders per change, and per cluster.
H --score "$R/.polaris/hops-plan.tsv" | tr -d '\r'

# 4. --owned: froms and tos, each Unity asset's .meta (now and after), the @/ importer src/App.tsx, the
#    test importing the moved calls, and docs/cart.md, which names two of them by their tails.
H --owned "$R/.polaris/hops-plan.tsv" | tr -d '\r'

# 5. --proof from a task worktree, the plan given RELATIVE: not in the worktree, so the primary's.
git -C "$R" worktree add -q "$WT" -b feat/T-1 >/dev/null 2>&1
P() { ( cd "$1" && shift && POLARIS_ROOT="$R" python "$PY" hops --proof "$@" 2>&1 ); printf 'rc=%s\n' "$?"; }
( cd "$WT"
  mkdir -p src/cart Assets/Scripts/coin
  while IFS="$(printf '\t')" read -r k f t; do
    git mv "$f" "$t"; [ ! -e "$f.meta" ] || git mv "$f.meta" "$t.meta"
  done < "$R/.polaris/hops-plan.tsv"
  rw src/App.tsx 's#@/components/CartView#@/cart/CartView#'
  rw src/cart/CartView.tsx 's#"@/hooks/useCart"#"./useCart"#'
  rw src/cart/useCart.ts 's#@/services/cartApi#@/cart/cartApi#'
  rw src/cart/cartApi.ts 's#"./http"#"../services/http"#'
  rw src/cart/cart.test.ts 's#@/services/cartApi#@/cart/cartApi#'
  rw docs/cart.md 's#services/cartApi#cart/cartApi#; s#components/CartView#cart/CartView#'
  printf '<!-- polaris:guide -->\n# src/cart/ — the cart: its screen, hook, calls and test\n<!-- /polaris:guide -->\n' > src/cart/CLAUDE.md
  printf '# path\tverdict\twhy — the layout record; polaris hops never proposes a keep row\nsrc/components/CartView.tsx\tmoved\t→ src/cart/CartView.tsx · hops-6.12.0\n' > ops/LAYOUT.tsv
  printf '# Shop\n<!-- POLARIS:END -->\n<!-- polaris:where -->\n## Where things live\n- `src/cart/` — the cart · guide\n<!-- /polaris:where -->\n' > CLAUDE.md
  git add -A ) >/dev/null 2>&1
echo '--- a pure move: green'
P "$WT" .polaris/hops-plan.tsv | tr -d '\r'
echo '--- one logic edit inside a moved file: red'
cp "$WT/src/cart/cartApi.ts" "$FIX/keep.ts"; rw "$WT/src/cart/cartApi.ts" 's#total \* 0.9#total * 0.8#'
P "$WT" .polaris/hops-plan.tsv | tr -d '\r'
cp "$FIX/keep.ts" "$WT/src/cart/cartApi.ts"
echo '--- landed on main: the same plan, the same verify line, still green'
( cd "$WT" && git commit -qm 'layout: the cart in one folder' && git -C "$R" merge -q --ff-only feat/T-1 ) >/dev/null 2>&1
P "$R" .polaris/hops-plan.tsv | tr -d '\r'

# 6. More proofs on main's tree, each from a clean one: a plan file per case.
plan() { printf '%s\n' "$@" | tr '|' '\t' > "$FIX/p.tsv"; }
clean() { ( cd "$R" && git reset -q --hard && git clean -fdq ) >/dev/null 2>&1; }
echo '--- a Java package line is not a path: red'
plan 'move|java/src/shop/Money.java|java/src/cart/Money.java'
( cd "$R" && mkdir -p java/src/cart && git mv java/src/shop/Money.java java/src/cart/Money.java && rw java/src/cart/Money.java 's#^package shop;#package cart;#' ) >/dev/null 2>&1
P "$R" "$FIX/p.tsv" | tr -d '\r'; clean
echo '--- an unplanned deletion, a move not made, a copy git does not track: red'
plan 'move|src/services/http.ts|src/net/http.ts' 'move|scripts/cart_report.py|scripts/reports/cart_report.py'
( cd "$R" && git rm -q src/utils/round.ts && mkdir -p scripts/reports && cp scripts/cart_report.py scripts/reports/ && rm scripts/cart_report.py ) >/dev/null 2>&1
P "$R" "$FIX/p.tsv" | tr -d '\r'; clean
echo '--- a python module moved, its dotted names rewritten: green'
plan 'move|scripts/cart_report.py|scripts/reports/cart_report.py'
( cd "$R" && mkdir -p scripts/reports && git mv scripts/cart_report.py scripts/reports/cart_report.py && rw scripts/nightly.py 's#scripts\.cart_report#scripts.reports.cart_report#g' ) >/dev/null 2>&1
P "$R" "$FIX/p.tsv" | tr -d '\r'; clean
echo '--- a merge: round.ts folded whole into money.ts, its import gone: green · a line of it dropped: red'
plan 'merge|src/utils/round.ts|src/utils/money.ts'
( cd "$R" && git rm -q src/utils/round.ts && rw src/utils/money.ts '/^import/d' && printf 'export function round2(x: number) {\n  return Math.round(x * 100) / 100;\n}\n' >> src/utils/money.ts ) >/dev/null 2>&1
P "$R" "$FIX/p.tsv" | tr -d '\r'
rw "$R/src/utils/money.ts" '/Math.round/d'
P "$R" "$FIX/p.tsv" | tr -d '\r'; clean
echo '--- a guides-only pass (an empty plan): a new guide, a map line, LAYOUT.tsv: green · text outside a block: red'
plan
( cd "$R" && printf '<!-- polaris:guide -->\n# src/utils/ — money maths\n<!-- /polaris:guide -->\n' > src/utils/CLAUDE.md \
  && rw CLAUDE.md 's#the cart · guide#the cart, in one folder · guide#' && printf 'src/utils/\tkeep\tunsure — left for you\n' >> ops/LAYOUT.tsv \
  && git add -A ) >/dev/null 2>&1
P "$R" "$FIX/p.tsv" | tr -d '\r'
( cd "$R" && rw CLAUDE.md 's|^# Shop$|# The shop|' && printf 'my notes\n<!-- polaris:guide -->\n# src/services/ — the calls\n<!-- /polaris:guide -->\n' > src/services/CLAUDE.md && git add -A ) >/dev/null 2>&1
P "$R" "$FIX/p.tsv" | tr -d '\r'; clean

# 7. --remap: the harness baseline follows the moves — a python module by its dotted name, a node
#    module by its path, a merged one dropped; scripts.gone was never moved, so it stays and still fails.
printf '{\n  "modules": [\n    "scripts.cart_report",\n    "scripts.gone",\n    "src/utils/round.js",\n    "tools/legacy.js"\n  ],\n  "routes": [\n    "/cart"\n  ]\n}\n' > "$R/.polaris/harness-baseline.json"
plan 'move|scripts/cart_report.py|scripts/reports/cart_report.py' 'move|tools/legacy.js|src/legacy.js' 'merge|src/utils/round.js|src/utils/money.js'
H --remap "$FIX/p.tsv" | tr -d '\r'
tr -d '\r' < "$R/.polaris/harness-baseline.json"
rm "$R/.polaris/harness-baseline.json"
H --remap "$FIX/p.tsv" | tr -d '\r'

# 8. A relative plan resolves against the current directory FIRST: the worktree's own copy wins.
mkdir -p "$WT/.polaris"
printf 'move\tsrc/utils/round.ts\tsrc/money/round.ts\n' > "$WT/.polaris/hops-plan.tsv"
( cd "$WT" && POLARIS_ROOT="$R" python "$PY" hops --owned .polaris/hops-plan.tsv 2>&1 | tr -d '\r' )

# 9. A missing or malformed plan, or a plan flag without one: ONE usage line on stderr, rc 2.
U() { err="$( POLARIS_ROOT="$R" python "$PY" hops "$@" 2>&1 >/dev/null )"; rc=$?; err="${err//$'\r'/}"
      printf '%s · %s line(s) · %s\n' "rc=$rc" "$(printf '%s\n' "$err" | grep -c .)" "${err%%]*}]"; }
printf 'no such plan: '; U --proof "$FIX/none.tsv"
for c in 'a folder|move\tsrc/utils/\tsrc/money/\n' 'a .meta|move\tAssets/Scripts/UI/CoinView.cs.meta\tx.cs.meta\n' \
         'moved twice|move\tsrc/a.ts\tsrc/b.ts\nmove\tsrc/a.ts\tsrc/c.ts\n' 'moved and a destination|move\tsrc/a.ts\tsrc/b.ts\nmove\tsrc/b.ts\tsrc/c.ts\n' \
         'not move or merge|shift\tsrc/a.ts\tsrc/b.ts\n' 'two fields|move\tsrc/a.ts\n'; do
  printf "${c#*|}" > "$FIX/bad.tsv"; printf '%s: ' "${c%%|*}"; U --owned "$FIX/bad.tsv"
done
printf -- '--score alone: '; U --score
printf -- '--remap with two plans: '; U --remap "$FIX/p.tsv" "$FIX/p.tsv"
