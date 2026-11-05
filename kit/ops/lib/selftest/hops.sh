# lib/selftest/hops.sh — the practice shop the layout work proves itself on (ops/contracts/save-hops.md
# § 8.2). Definitions only, nothing runs when sourced; T-252 adds this file to the loader list.
hops_fixture() { # hops_fixture <new-dir> — build the shop there from nothing, the same commit ids on any machine
  # A storefront sorted by KIND of file (src/components hooks services utils types + tests/) whose
  # four features — checkout, profile, search, billing — each sit across 3+ of those folders and
  # reach each other through @/ imports, with 120 commits of history. Planted with bait the layout
  # pass must never move: a Unity Resources asset + its .meta, a published package
  # (packages/ui-kit), a SURFACES-covered pair, src/legacy/ under a RULES path rule, a LAYOUT keep
  # row and a Java file. Every bait file changes together with checkout, so only the FIXED rules
  # keep it out of checkout's cluster. Bait never imports a movable file: moving one never needs an
  # edit inside a file the pass may not touch.
  # ONE `git fast-import` stream writes the whole history: a commit costs no process of its own (on
  # Git Bash every fork is ~240 ms, so 120 porcelain commits would blow the 30 s budget), and the
  # stream is the determinism — fixed author, committer, dates and content, and fast-import never
  # runs a hook or signs. The files live in shell variables (b_<path with _ for every other char>)
  # while the stream is written; `git reset --hard` then puts the final tree on disk.
  local dir="${1:-}"
  if [ -z "$dir" ]; then printf '⛔ usage: hops_fixture <new-dir>\n' >&2; return 2; fi
  if [ -e "$dir" ]; then printf '⛔ hops_fixture: %s already exists — name a directory that does not\n' "$dir" >&2; return 1; fi
  git init -q -b main "$dir" 2>/dev/null || { git init -q "$dir" && git -C "$dir" symbolic-ref HEAD refs/heads/main; } || return 1
  # An identity for whoever commits in the shop next (the drill, a tidy pass), and LF on every
  # checkout. Appended as text: three `git config` calls would cost three forks for the same bytes.
  printf '[core]\n\tautocrlf = false\n[user]\n\tname = Fixture Shop\n\temail = shop@fixture-shop.test\n' >> "$dir/.git/config" || return 1
  ( set -fu
    tab=$'\t'
    c=0
    # 1. The files the shop starts with. `@commit <message>` opens a commit, `@file <path>` a file
    #    inside it; in .tsv files `<TAB>` stands for a real TAB.
    while IFS= read -r l; do
      case "$l" in
        '@commit '*) c=$((c + 1)); printf -v "m_$c" '%s' "${l#@commit }"; printf -v "t_$c" '%s' '' ;;
        '@file '*) p=${l#@file }; k="b_${p//[^A-Za-z0-9]/_}"; printf -v "$k" '%s' ''
                   kt="t_$c"; printf -v "$kt" '%s %s' "${!kt}" "$p" ;;
        *) case "$p" in *.tsv) l=${l//<TAB>/$tab} ;; esac
           printf -v "$k" '%s%s\n' "${!k}" "$l" ;;
      esac
    done <<'SHOP'
@commit shop: start the storefront with an import check
@file package.json
{"name": "fixture-shop", "private": true, "scripts": {"test": "bash tests/run.sh"}}
@file tsconfig.json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    },
    "jsx": "react-jsx",
    "strict": true
  }
}
@file README.md
# fixture-shop

A small storefront with four features: checkout, profile, search and billing.

Check it with `bash tests/run.sh`: it fails when an import points at a file that is not there.
@file .gitignore
node_modules/
.polaris/
@file tests/run.sh
#!/usr/bin/env bash
# The shop's check: every @/ import must reach src/<path>.ts or src/<path>.tsx, and every relative
# import must reach a file. Exits 1 naming the first import that does not.
cd "$(dirname "$0")/.." || exit 1
q='"'
files=$(find src tests -type f \( -name '*.ts' -o -name '*.tsx' \) | LC_ALL=C sort)
grep -H "^import .* from $q" /dev/null $files | while IFS= read -r line; do
  file=${line%%:*}
  spec=${line#* from $q}
  spec=${spec%%$q*}
  case "$spec" in
    @/*) want="src/${spec#@/}"
      [ -f "$want.ts" ] || [ -f "$want.tsx" ] || { echo "broken import: $file imports $spec (no $want.ts or $want.tsx)"; exit 1; } ;;
    ./*|../*) want="${file%/*}/$spec"
      [ -f "$want" ] || [ -f "$want.ts" ] || [ -f "$want.tsx" ] || [ -f "$want.js" ] || { echo "broken import: $file imports $spec (nothing at $want)"; exit 1; } ;;
  esac
done || exit 1
echo "ok: every import resolves"
@commit checkout: cart, coupons, tax and the pay button
@file src/types/checkout.ts
export interface CartItem {
  sku: string;
  name: string;
  priceCents: number;
  quantity: number;
}

export interface Coupon {
  code: string;
  percentOff: number;
}
@file src/utils/taxRate.ts
const RATES: Record<string, number> = { EU: 20, UK: 20, US: 7 };

export function taxRateFor(region: string): number {
  return (RATES[region] ?? 0) / 100;
}
@file src/utils/cartTotal.ts
import type { CartItem } from "@/types/checkout";
import { taxRateFor } from "@/utils/taxRate";

export function computeCartTotal(items: CartItem[], region: string): number {
  const subtotal = items.reduce((sum, item) => sum + item.priceCents * item.quantity, 0);
  return Math.round(subtotal * (1 + taxRateFor(region)));
}
@file src/legacy/couponCodes.ts
// Coupon codes carried over from the old shop. Frozen: finance signs off every change.
export const LEGACY_COUPONS: Record<string, number> = {
  WELCOME5: 5,
  SPRING10: 10,
};
@file src/payments/gateway.ts
// The payment provider's SDK loads this file by its path, so it stays exactly here.
export async function chargeCard(amountCents: number, cardToken: string): Promise<boolean> {
  return amountCents > 0 && cardToken.length > 0;
}
@file src/services/checkoutApi.ts
import type { CartItem, Coupon } from "@/types/checkout";
import { LEGACY_COUPONS } from "@/legacy/couponCodes";
import { chargeCard } from "@/payments/gateway";
import { computeCartTotal } from "@/utils/cartTotal";

export function applyCoupon(totalCents: number, coupon: Coupon | undefined): number {
  if (!coupon) return totalCents;
  const percent = LEGACY_COUPONS[coupon.code] ?? coupon.percentOff;
  return Math.round(totalCents * (1 - percent / 100));
}

export async function submitOrder(items: CartItem[], region: string, coupon: Coupon | undefined, cardToken: string) {
  return chargeCard(applyCoupon(computeCartTotal(items, region), coupon), cardToken);
}
@file src/hooks/useCheckout.ts
import type { CartItem, Coupon } from "@/types/checkout";
import { applyCoupon, submitOrder } from "@/services/checkoutApi";
import { computeCartTotal } from "@/utils/cartTotal";

export function useCheckout(items: CartItem[], region: string) {
  let coupon: Coupon | undefined;
  return {
    total: () => applyCoupon(computeCartTotal(items, region), coupon),
    setCoupon: (next: Coupon) => {
      coupon = next;
    },
    pay: (cardToken: string) => submitOrder(items, region, coupon, cardToken),
  };
}
@file packages/ui-kit/package.json
{
  "name": "ui-kit",
  "version": "1.0.0",
  "main": "index.js"
}
@file packages/ui-kit/index.js
// ui-kit: the shop's buttons, published on their own so the game shop can use them too.
export function Button({ label, onClick }) {
  return { type: "button", label, onClick };
}
@file src/components/CartLine.tsx
import type { CartItem } from "@/types/checkout";

export function CartLine({ item }: { item: CartItem }) {
  return (
    <li>
      {item.name} x{item.quantity} {((item.priceCents * item.quantity) / 100).toFixed(2)}
    </li>
  );
}
@file src/components/CheckoutForm.tsx
import { Button } from "../../packages/ui-kit/index.js";
import type { CartItem } from "@/types/checkout";
import { useCheckout } from "@/hooks/useCheckout";
import { CartLine } from "./CartLine";

export function CheckoutForm({ items, region }: { items: CartItem[]; region: string }) {
  const checkout = useCheckout(items, region);
  return (
    <form>
      <ul>
        {items.map((item) => (
          <CartLine key={item.sku} item={item} />
        ))}
      </ul>
      <p>Total {(checkout.total() / 100).toFixed(2)}</p>
      <Button label="Pay" onClick={() => checkout.pay("saved-card")} />
    </form>
  );
}
@file tests/checkout.test.ts
import { applyCoupon } from "@/services/checkoutApi";

test("a coupon takes its percent off the total", () => {
  expect(applyCoupon(2000, { code: "SAVE10", percentOff: 10 })).toBe(1800);
});

test("no coupon leaves the total as it is", () => {
  expect(applyCoupon(2000, undefined)).toBe(2000);
});
@file tests/cartTotal.test.ts
import type { CartItem } from "@/types/checkout";
import { computeCartTotal } from "@/utils/cartTotal";

const mugs: CartItem[] = [{ sku: "mug", name: "Mug", priceCents: 1000, quantity: 2 }];

test("the total adds the region's tax", () => {
  expect(computeCartTotal(mugs, "US")).toBe(2140);
});
@file tests/taxRate.test.ts
import { taxRateFor } from "@/utils/taxRate";

test("a region with no rate pays no tax", () => {
  expect(taxRateFor("XX")).toBe(0);
});
@commit profile: the profile card and avatar upload
@file src/types/profile.ts
export interface Profile {
  id: string;
  displayName: string;
  avatarUrl?: string;
  bio: string;
}
@file src/services/profileApi.ts
import type { Profile } from "@/types/profile";

export async function fetchProfile(id: string): Promise<Profile> {
  const res = await fetch("/api/profiles/" + id);
  return res.json();
}

export async function uploadAvatar(id: string, file: Blob): Promise<string> {
  const body = new FormData();
  body.append("avatar", file);
  const res = await fetch("/api/profiles/" + id + "/avatar", { method: "POST", body });
  return (await res.json()).url;
}
@file src/hooks/useProfile.ts
import type { Profile } from "@/types/profile";
import { fetchProfile, uploadAvatar } from "@/services/profileApi";

export function useProfile(id: string) {
  let profile: Profile | undefined;
  return {
    load: async () => {
      profile = await fetchProfile(id);
      return profile;
    },
    changeAvatar: (file: Blob) => uploadAvatar(id, file),
  };
}
@file src/components/AvatarImage.tsx
export function AvatarImage({ url, name }: { url?: string; name: string }) {
  if (!url) return <span className="avatar">{name.slice(0, 1)}</span>;
  return <img className="avatar" src={url} alt={name} />;
}
@file src/components/ProfileCard.tsx
import type { Profile } from "@/types/profile";
import { useProfile } from "@/hooks/useProfile";
import { AvatarImage } from "./AvatarImage";

export function ProfileCard({ profile }: { profile: Profile }) {
  const actions = useProfile(profile.id);
  return (
    <section>
      <AvatarImage url={profile.avatarUrl} name={profile.displayName} />
      <h2>{profile.displayName}</h2>
      <p>{profile.bio}</p>
      <input type="file" onChange={(e) => e.target.files && actions.changeAvatar(e.target.files[0])} />
    </section>
  );
}
@file tests/profile.test.ts
import { uploadAvatar } from "@/services/profileApi";

test("uploadAvatar is ready to send a file", () => {
  expect(typeof uploadAvatar).toBe("function");
});
@commit search: the search bar with debounced results
@file src/types/search.ts
export interface SearchResult {
  sku: string;
  title: string;
}
@file src/services/searchApi.ts
import type { SearchResult } from "@/types/search";

export async function searchProducts(query: string): Promise<SearchResult[]> {
  const res = await fetch("/api/search?q=" + encodeURIComponent(query));
  return res.json();
}
@file src/hooks/useSearch.ts
import type { SearchResult } from "@/types/search";
import { searchProducts } from "@/services/searchApi";

export function debounceQuery(run: (query: string) => void, waitMs = 250) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return (query: string) => {
    if (timer) clearTimeout(timer);
    timer = setTimeout(() => run(query), waitMs);
  };
}

export function useSearch(onResults: (results: SearchResult[]) => void) {
  return debounceQuery(async (query) => onResults(await searchProducts(query)));
}
@file src/hooks/useRecentSearches.ts
const recent: string[] = [];

export function useRecentSearches() {
  return {
    add: (query: string) => {
      recent.unshift(query);
      recent.length = Math.min(recent.length, 5);
    },
    list: () => recent.slice(),
  };
}
@file src/utils/searchHighlight.ts
export function highlightMatches(text: string, query: string): string {
  if (!query) return text;
  return text.split(query).join("<mark>" + query + "</mark>");
}
@file src/components/SearchResults.tsx
import type { SearchResult } from "@/types/search";
import { highlightMatches } from "@/utils/searchHighlight";

export function SearchResults({ results, query }: { results: SearchResult[]; query: string }) {
  return (
    <ul>
      {results.map((result) => (
        <li key={result.sku} dangerouslySetInnerHTML={{ __html: highlightMatches(result.title, query) }} />
      ))}
    </ul>
  );
}
@file src/components/SearchBar.tsx
import { useSearch } from "@/hooks/useSearch";
import { useRecentSearches } from "@/hooks/useRecentSearches";
import { SearchResults } from "./SearchResults";

export function SearchBar() {
  const recent = useRecentSearches();
  const search = useSearch((results) => console.log(results.length + " results"));
  return (
    <div>
      <input
        placeholder="Search the shop"
        onChange={(e) => {
          recent.add(e.target.value);
          search(e.target.value);
        }}
      />
      <SearchResults results={[]} query="" />
    </div>
  );
}
@file tests/search.test.ts
import { debounceQuery } from "@/hooks/useSearch";

test("debounceQuery runs once for a burst of keystrokes", () => {
  const seen: string[] = [];
  const run = debounceQuery((query) => seen.push(query), 0);
  run("m");
  run("mu");
  run("mug");
  expect(seen.length).toBeLessThan(3);
});
@commit billing: invoices and the billing summary
@file src/types/billing.ts
export interface Invoice {
  id: number;
  issuedOn: string;
  amountCents: number;
  paid: boolean;
}
@file src/utils/invoiceFormat.ts
export function formatInvoiceNumber(id: number, year: number): string {
  return "INV-" + year + "-" + String(id).padStart(5, "0");
}
@file src/services/billingApi.ts
import type { Invoice } from "@/types/billing";

export async function fetchInvoices(): Promise<Invoice[]> {
  const res = await fetch("/api/invoices");
  return res.json();
}
@file src/services/paymentMethods.ts
export interface CardOnFile {
  brand: string;
  lastDigits: string;
}

export async function fetchCardOnFile(): Promise<CardOnFile | undefined> {
  const res = await fetch("/api/billing/card");
  return res.ok ? res.json() : undefined;
}
@file src/hooks/useBilling.ts
import type { Invoice } from "@/types/billing";
import { fetchInvoices } from "@/services/billingApi";
import { fetchCardOnFile } from "@/services/paymentMethods";

export function useBilling() {
  let invoices: Invoice[] = [];
  return {
    load: async () => {
      invoices = await fetchInvoices();
      return fetchCardOnFile();
    },
    unpaid: () => invoices.filter((invoice) => !invoice.paid),
  };
}
@file src/components/InvoiceList.tsx
import type { Invoice } from "@/types/billing";
import { formatInvoiceNumber } from "@/utils/invoiceFormat";

export function InvoiceList({ invoices }: { invoices: Invoice[] }) {
  return (
    <table>
      <tbody>
        {invoices.map((invoice) => (
          <tr key={invoice.id}>
            <td>{formatInvoiceNumber(invoice.id, Number(invoice.issuedOn.slice(0, 4)))}</td>
            <td>{(invoice.amountCents / 100).toFixed(2)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}
@file src/components/BillingSummary.tsx
import { useBilling } from "@/hooks/useBilling";
import { InvoiceList } from "./InvoiceList";

export function BillingSummary() {
  const billing = useBilling();
  return (
    <section>
      <h2>Billing</h2>
      <InvoiceList invoices={billing.unpaid()} />
    </section>
  );
}
@file tests/billing.test.ts
import { formatInvoiceNumber } from "@/utils/invoiceFormat";

test("an invoice number carries the year and five digits", () => {
  expect(formatInvoiceNumber(42, 2025)).toBe("INV-2025-00042");
});
@commit shop: one App page that shows every feature
@file src/App.tsx
import { CheckoutForm } from "@/components/CheckoutForm";
import { ProfileCard } from "@/components/ProfileCard";
import { SearchBar } from "@/components/SearchBar";
import { BillingSummary } from "@/components/BillingSummary";

export function App() {
  return (
    <main>
      <SearchBar />
      <CheckoutForm items={[]} region="US" />
      <ProfileCard profile={{ id: "me", displayName: "Me", bio: "" }} />
      <BillingSummary />
    </main>
  );
}
@commit rewards: the coin the game shop sells
@file Assets/Resources/Coin.asset
%YAML 1.1
%TAG !u! tag:unity3d.com,2011:
--- !u!114 &11400000
MonoBehaviour:
  m_ObjectHideFlags: 0
  m_Name: Coin
  priceCents: 99
  rewardPerOrder: 1
@file Assets/Resources/Coin.asset.meta
fileFormatVersion: 2
guid: 8f3a6c1d2b4e4f5a9c7d0e1f2a3b4c5d
NativeFormatImporter:
  externalObjects: {}
  mainObjectFileID: 11400000
  userData:
  assetBundleName:
  assetBundleVariant:
@commit server: the Money type the order service shares
@file java/src/shop/Money.java
package shop;

public final class Money {
    private final long cents;

    public Money(long cents) {
        this.cents = cents;
    }

    public long cents() {
        return cents;
    }

    public Money plus(Money other) {
        return new Money(cents + other.cents);
    }
}
@commit chore: write down the shop's working rules
@file ops/CONVENTIONS.md
# CONVENTIONS
base: main
test: bash tests/run.sh
@file ops/RULES.tsv
# scope<TAB>kind<TAB>pattern<TAB>message
src/legacy/<TAB>path<TAB>-<TAB>the old coupon table is frozen: finance signs off every change
@file ops/SURFACES.tsv
# surface<TAB>tests<TAB>cmd<TAB>note
src/utils/taxRate.ts<TAB>tests/taxRate.test.ts<TAB>bash tests/run.sh<TAB>the tax table checkout charges
@file ops/LAYOUT.tsv
# path<TAB>verdict<TAB>why — the layout record; polaris hops never proposes a keep row
src/payments/gateway.ts<TAB>keep<TAB>framework convention
SHOP
    # 2. Steps 1..c replay the blocks above; every later step is one feature's work across its
    #    folders (a window of 2-4 of its files, sliding by 5) — checkout 3 changes in 9, the
    #    others 2 — and every 12th is a one-file fix. Each touched file gains one line, so no
    #    step is empty; ui-kit's package.json bumps its version instead, so it stays valid JSON.
    who='Fixture Shop <shop@fixture-shop.test>'
    names=(checkout profile search billing)
    rot=(0 1 0 2 3 0 2 1 3)
    cnt=(0 0 0 0)
    fixes=('src/components/SearchBar.tsx|search: correct the placeholder typo'
           'src/utils/invoiceFormat.ts|billing: keep invoice numbers at five digits'
           'src/services/profileApi.ts|profile: refuse avatars over 2 MB'
           'tests/run.sh|tests: name the file that holds a broken import'
           'src/components/CartLine.tsx|checkout: show the quantity on narrow screens'
           'src/hooks/useRecentSearches.ts|search: keep five recent searches'
           'src/components/BillingSummary.tsx|billing: hide the summary when nothing is due'
           'src/types/profile.ts|profile: allow an empty bio'
           'src/components/AvatarImage.tsx|profile: fall back to initials when an image breaks')
    nf=${#fixes[@]}
    s=0; q=0; v=0; ts=1735725600
    while [ "$s" -lt 120 ]; do
      s=$((s + 1))
      if [ "$s" -le "$c" ]; then
        km="m_$s"; kt="t_$s"; msg=${!km}; touch=${!kt}
      elif [ $(( (s - c) % 12 )) -eq 0 ]; then
        fx=${fixes[q % nf]}; q=$((q + 1)); touch=${fx%%|*}; msg=${fx#*|}
      else
        f=${rot[(s - c) % 9]}; r=${cnt[f]}; cnt[f]=$((r + 1))
        case "$f" in
          0) fl=(src/components/CheckoutForm.tsx src/hooks/useCheckout.ts src/services/checkoutApi.ts
                 tests/checkout.test.ts src/utils/cartTotal.ts tests/cartTotal.test.ts
                 src/types/checkout.ts src/components/CartLine.tsx)
             ph=('handle an empty cart' 'show the coupon error next to the field' 'round the total to the cent'
                 'keep the cart after a failed payment' 'disable Pay while the order is sent'
                 'list the tax line on the receipt' 'remember the last coupon' 'tidy the order summary') ;;
          1) fl=(src/components/ProfileCard.tsx src/hooks/useProfile.ts src/services/profileApi.ts
                 tests/profile.test.ts src/types/profile.ts src/components/AvatarImage.tsx)
             ph=('show initials when there is no avatar' 'trim the display name' 'crop avatars to a square'
                 'retry a failed avatar upload' 'show the member-since date' 'tidy the profile form') ;;
          2) fl=(src/components/SearchBar.tsx src/hooks/useSearch.ts src/services/searchApi.ts
                 tests/search.test.ts src/utils/searchHighlight.ts src/components/SearchResults.tsx
                 src/types/search.ts src/hooks/useRecentSearches.ts)
             ph=('ignore queries shorter than two letters' 'highlight every match'
                 'keep the cursor in place while results load' 'drop answers to stale queries'
                 'show a hint when nothing matches' 'tidy the results list') ;;
          3) fl=(src/components/BillingSummary.tsx src/hooks/useBilling.ts src/services/billingApi.ts
                 tests/billing.test.ts src/utils/invoiceFormat.ts src/components/InvoiceList.tsx
                 src/types/billing.ts src/services/paymentMethods.ts)
             ph=('sort invoices newest first' 'show the due date' 'mark overdue invoices'
                 'show the card on file' 'group invoices by year' 'tidy the billing summary') ;;
        esac
        n=${#fl[@]}; j=0; touch=''
        while [ "$j" -lt $((2 + r % 3)) ]; do touch="$touch ${fl[(r * 5 + j) % n]}"; j=$((j + 1)); done
        # Checkout drags one piece of bait along every time, round robin, TOGETHER with the checkout
        # file that uses it (the first word): a bait file that never changes 3 times with the same
        # checkout file never joins its cluster, and bait nothing would propose proves nothing.
        if [ "$f" -eq 0 ]; then
          b=$((r % 6))
          case "$b" in
            0) bait='src/components/CheckoutForm.tsx Assets/Resources/Coin.asset Assets/Resources/Coin.asset.meta' ;;
            1) bait='src/components/CheckoutForm.tsx packages/ui-kit/index.js packages/ui-kit/package.json' ;;
            2) bait='src/services/checkoutApi.ts src/legacy/couponCodes.ts' ;;
            3) bait='src/services/checkoutApi.ts src/payments/gateway.ts' ;;
            4) bait='src/utils/cartTotal.ts src/utils/taxRate.ts tests/taxRate.test.ts' ;;
            5) bait='src/services/checkoutApi.ts java/src/shop/Money.java' ;;
          esac
          for p in $bait; do
            case " $touch " in *" $p "*) ;; *) touch="$touch $p" ;; esac
          done
        fi
        np=${#ph[@]}; msg="${names[f]}: ${ph[r % np]}"
      fi
      ts=$((ts + 14400 + s % 5 * 3600))
      printf 'commit refs/heads/main\nauthor %s %s +0000\ncommitter %s %s +0000\ndata <<SHOP_EOF\n%s\nSHOP_EOF\n' \
        "$who" "$ts" "$who" "$ts" "$msg"
      for p in $touch; do
        k="b_${p//[^A-Za-z0-9]/_}"
        if [ "$s" -gt "$c" ]; then
          case "$p" in
            packages/ui-kit/package.json) v=$((v + 1))
              printf -v "$k" '{\n  "name": "ui-kit",\n  "version": "1.%s.0",\n  "main": "index.js"\n}\n' "$v" ;;
            *.asset|*.meta|*.sh) printf -v "$k" '%s# %s (change %s)\n' "${!k}" "$msg" "$s" ;;
            *) printf -v "$k" '%s// %s (change %s)\n' "${!k}" "$msg" "$s" ;;
          esac
        fi
        printf 'M 100644 inline %s\ndata <<SHOP_EOF\n%sSHOP_EOF\n' "$p" "${!k}"
      done
    done
    printf 'done\n'
  ) | git -C "$dir" fast-import --quiet --done || return 1
  git -C "$dir" reset -q --hard
}
