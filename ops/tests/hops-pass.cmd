# hops-pass: one layout pass as `polaris hops` sees it, from its worktree to its land
# (ops/contracts/save-hops.md § 12.1-§ 12.5). The first real pass, on this very shop, was misread
# three ways: from its worktree, its own branch and its own staged edits counted as somebody else's
# work in progress, so every file it moved was frozen — no guides offered for the new folders, and
# the wrong after-score; after `done` its kept branch froze the same files on main until a sweep;
# and its land commit, under the 40-path skip, counted as one ordinary change that tied every
# feature together through src/App.tsx (and read 1.34 where the moves made 1.31), so the cluster
# it left behind was never proposed again. Here the pass is walked again, the way the 6.12.0 one
# went: the first 25 MOVE rows (one pass's cap) — checkout, billing, profile and three of search's
# eight files. Beside it, what a pass is handed now (§ 12.4, § 12.5).
#   1. main before the pass: --score says the plan takes 2.80 folders per change to 1.31.
#   2. the cut a pass takes now: --propose moves whole features only — checkout, billing and
#      profile; search's eight wait whole for the next pass. --score and --due weigh exactly those
#      rows (52% both), and --owned names the whole task: every row, the one importer, the three
#      guides the moves call for, CLAUDE.md and ops/LAYOUT.tsv.
#   3. the worktree, a first step: five rows moved, their imports fixed, committed. --owned for the
#      next five, asked of the worktree, names each importer where it lives NOW, and the one guide
#      the worktree's layout calls for; main's answer still names the old paths, and guides for
#      folders the first step emptied (F7).
#   4. the other 20 moves committed (and pushed), importers fixed but only staged: --tsv counts
#      every moved file where it now lives and asks for a guide in each new folder of 5+ files.
#   5. the pass commits, writes those guides, commits again: line 1 says the 1.31 --score promised.
#   6. the land: ONE squash commit on main with the LAYOUT.tsv rows in it, T-1 in done/ on the board
#      ref, feat/T-1 kept here and on origin.
#   7. main reads exactly what the worktree read, and the five search files left behind keep their
#      MOVE rows — --propose offers them whole, the next pass. The guides' headings show the purpose
#      rule: `<dir>/ — ` goes once, and only when text follows it.
#   8. a task that is NOT finished still holds the file it changes, seen from the worktree too.
#   9. a second repo pins the cut's edges: three features of 10, 16 and 15 files — the 16 would pass
#      25, so it waits whole and the walk goes on to the 15 behind it: exactly 25, both whole, and
#      --due weighs those very rows (44%, where the first 25 MOVE rows would say 39%).
#
# HERMETIC (the keys-drift pattern): the practice shop (hops_fixture, § 8.2) under mktemp -d, its
# board ref planted by fast-import — no POLARIS install. THE ENGINE TRAP (§ 8.4): the kit's code is
# reached as `POLARIS_ROOT=<shop or worktree> python kit/ops/index.py hops`.
PY="$(pwd)/kit/ops/index.py"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/shop"
WT="$R/.polaris/wt/T-1"
P="$R/.polaris/hops-plan.tsv"
bash -c '. kit/ops/lib/selftest/hops.sh; hops_fixture "$1"' _ "$R" >/dev/null 2>&1
H() { POLARIS_ROOT="$1" python "$PY" hops "${@:2}" 2>&1 | tr -d '\r'; }
# mvp <plan> — git mv each home's rows in ONE call, the way the 6.12.0 pass moved them
mvp() { for h in checkout billing profile search; do
          fs="$(awk -F'\t' -v h="src/$h/" 'index($3, h) == 1 { print $2 }' "$1")"
          [ -z "$fs" ] || { mkdir -p "src/$h" && git mv $fs "src/$h/"; } || return 1
        done; }
# fixup <plan> — every @/ import of a moved file follows it, and LAYOUT.tsv records each move
cat > "$FIX/fixup.py" <<'FIXUP'
import os, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    moves = [r.split("\t")[1:] for r in fh.read().split("\n") if r]
spec = lambda p: '"@/' + p[len("src/"):].rsplit(".", 1)[0] + '"'
subs = [(spec(f), spec(t)) for f, t in moves if f.startswith("src/")]
for top in ("src", "tests"):
    for d, _, names in os.walk(top):
        for p in [os.path.join(d, n) for n in names if n.endswith((".ts", ".tsx"))]:
            with open(p, encoding="utf-8", newline="") as fh:
                old = new = fh.read()
            for a, b in subs:
                new = new.replace(a, b)
            if new != old:
                with open(p, "w", encoding="utf-8", newline="") as fh:
                    fh.write(new)
with open("ops/LAYOUT.tsv", "a", encoding="utf-8", newline="") as fh:
    fh.writelines("%s\tmoved\t→ %s · hops-6.13.0\n" % (f, t) for f, t in moves)
FIXUP

echo '--- 1. main before the pass: the plan is the first 25 MOVE rows'
mkdir -p "$R/.polaris"
H "$R" --tsv | awk -F'\t' '$1 == "MOVE" && n++ < 25 { print "move\t" $2 "\t" $3 }' > "$P"
H "$R" --score "$P"

echo '--- 2. the cut a pass takes now: --propose, whole features only — search waits whole'
PP="$R/.polaris/hops-proposal.tsv"
H "$R" --propose > "$PP"
cat "$PP"
H "$R" --score "$PP"
H "$R" --due
H "$R" --owned "$PP" | awk -F'\t' 'NR == FNR { plan[$2]; plan[$3]; n += 2; next }
  ($0 in plan) { k++; next } { more = more (more == "" ? "" : " · ") $0 }
  END { printf "--owned: %d of the plan'"'"'s %d paths, and %s\n", k, n, more }' "$PP" -
sed -n '1,5p' "$P" > "$FIX/step-1.tsv"
sed -n '6,10p' "$P" > "$FIX/step-2.tsv"
sed -n '6,$p' "$P" > "$FIX/rest.tsv"
H "$R" --owned "$FIX/step-2.tsv" > "$FIX/owned-main"

echo '--- 3. the worktree, a first step: five rows moved, their imports fixed, committed'
( cd "$R" && git worktree add -q "$WT" -b feat/T-1 && cd "$WT" \
  && mvp "$FIX/step-1.tsv" && git commit -qm 'layout: a first step, five files' \
  && python "$FIX/fixup.py" "$FIX/step-1.tsv" && git commit -qam 'layout: their imports follow' ) >/dev/null 2>&1
H "$WT" --owned "$FIX/step-2.tsv" | tee "$FIX/owned-wt"
printf "only main's answer: %s\n" "$(LC_ALL=C comm -23 "$FIX/owned-main" "$FIX/owned-wt" | paste -sd' ' -)"
printf "only the worktree's: %s\n" "$(LC_ALL=C comm -13 "$FIX/owned-main" "$FIX/owned-wt" | paste -sd' ' -)"

echo '--- 4. the worktree: the other 20 moves committed, importers fixed and staged'
( cd "$WT" && mvp "$FIX/rest.tsv" && git commit -qm 'layout: 20 more files into their feature folders' \
  && git update-ref refs/remotes/origin/feat/T-1 HEAD \
  && python "$FIX/fixup.py" "$FIX/rest.tsv" && git add -A ) >/dev/null 2>&1
TSV="$(H "$WT" --tsv)"
printf '%s\n' "$TSV"
printf '%s\n' "$TSV" | awk -F'\t' '$1 == "MAP" && $2 ~ /^src\/(checkout|billing|profile|search)\/$/ { n += $3 }
  END { printf "moved files counted where they now live: %d of 25\n", n }'

echo '--- 5. the pass commits, writes the guides --tsv asked for, commits: bare hops, line 1'
( cd "$WT" && git commit -qm 'layout: every import follows its file' \
  && printf '<!-- polaris:guide -->\n# src/checkout/ — the cart, its coupons and tax, and the pay button\n<!-- /polaris:guide -->\n' > src/checkout/CLAUDE.md \
  && printf '<!-- polaris:guide -->\n# src/billing/ — src/billing/ — invoices and the card on file\n<!-- /polaris:guide -->\n' > src/billing/CLAUDE.md \
  && printf '<!-- polaris:guide -->\n# src/profile/ — \n<!-- /polaris:guide -->\n' > src/profile/CLAUDE.md \
  && git add -A && git commit -qm 'layout: a guide for each new folder' ) >/dev/null 2>&1
L1="$(H "$WT" | sed -n 1p)"
printf '%s\n' "$L1"

echo '--- 6. the land: one commit on main, T-1 done on the board, its branch kept'
( cd "$R" && git merge -q --squash feat/T-1 && git commit -qm 'T-1: one layout pass' ) >/dev/null 2>&1
printf 'commit refs/heads/polaris/board\ncommitter Board <board@fixture-shop.test> 1767225600 +0000\ndata <<EOF\nboard: T-1 done\nEOF\nM 100644 inline ops/board/done/T-1.md\ndata <<EOF\n# T-1 one layout pass\nEOF\n\n' \
  | git -C "$R" fast-import --quiet >/dev/null 2>&1
git -C "$R" log -1 -M --name-status --format= main | awk -F'\t' 'NF > 1 { n++; if ($NF == "ops/LAYOUT.tsv") l = 1 }
  END { printf "land: one commit of %d paths, ops/LAYOUT.tsv %s\n", n, l ? "among them" : "not among them" }'
printf 'board: %s · kept: %s\n' "$(git -C "$R" ls-tree --name-only refs/heads/polaris/board -- ops/board/done/)" \
  "$(git -C "$R" for-each-ref --format='%(refname:short)' refs/heads/feat/ refs/remotes/origin/feat/ | awk '{ printf "%s%s", s, $0; s = " " }')"

echo '--- 7. main after the land: the same line 1, and the cluster left behind keeps its MOVE rows'
M1="$(H "$R" | sed -n 1p)"
printf '%s\n' "$M1"
[ "$M1" = "$L1" ] && echo 'line 1 on main = line 1 in the worktree' || echo 'line 1 on main differs from the worktree'
H "$R" --tsv
echo 'the next pass: --propose'
H "$R" --propose

echo '--- 8. an unfinished task holds what it changes, even seen from the worktree'
( cd "$R" && git checkout -qb feat/T-2 && printf '// wip\n' >> src/hooks/useSearch.ts \
  && git commit -qam 'search: wip' && git checkout -q main ) >/dev/null 2>&1
H "$WT" --tsv | awk -F'\t' '$1 == "MOVE" { n++; if ($2 == "src/hooks/useSearch.ts") h = 1 }
  END { printf "MOVE rows: %d · src/hooks/useSearch.ts among them: %s\n", n, h ? "yes" : "no" }'

echo '--- 9. a feature too big for what is left of the pass waits whole, and the walk goes on'
# alpha, bravo and charlie each sit across src/ui, src/api and src/lib and change as one, 5, 4 and
# 3 times — so they rank in that order — in ONE fast-import stream: every change rewrites each of
# its files, and a file is written first by the change that creates it.
C="$FIX/cut"
( git init -q -b main "$C" 2>/dev/null || { git init -q "$C"; git -C "$C" symbolic-ref HEAD refs/heads/main; }
  printf '[core]\n\tautocrlf = false\n' >> "$C/.git/config"
  feat() { # feat <name> <ui> <api> <lib> — the feature's files, numbered across its three folders
    nm="$1"; shift; i=0
    for d in ui api lib; do j=0; while [ "$j" -lt "$1" ]; do i=$((i + 1)); j=$((j + 1)); printf ' src/%s/%s%s.ts' "$d" "$nm" "$i"; done; shift; done; }
  A="$(feat alpha 4 3 3)"; B="$(feat bravo 6 5 5)"; X="$(feat charlie 5 5 5)"
  n=0
  { for c in "5 $A" "4 $B" "3 $X"; do
      set -- $c; k="$1"; shift
      while [ "$k" -gt 0 ]; do k=$((k - 1)); n=$((n + 1))
        printf 'commit refs/heads/main\ncommitter Cut <cut@cut.test> %s +0000\ndata <<EOF\nchange %s\nEOF\n' "$((1700000000 + n * 60))" "$n"
        for p in "$@"; do printf 'M 100644 inline %s\ndata <<EOF\nexport const v = %s;\nEOF\n' "$p" "$n"; done
        printf '\n'
      done
    done; printf 'done\n'; } | git -C "$C" fast-import --quiet --done
  git -C "$C" reset -q --hard ) >/dev/null 2>&1
H "$C" --tsv | awk -F'\t' '$1 == "SCATTER" { printf "%s%s %d files", s, $2, split($5, f, ","); s = " · " } END { print "" }'
H "$C" --propose > "$FIX/cut.tsv"
awk -F'\t' '{ d = $3; sub(/[^\/]*$/, "", d); if (!(d in n)) o[++k] = d; n[d]++ }
  END { printf "--propose: %d rows —", NR; for (i = 1; i <= k; i++) printf " %s%s %d", (i > 1 ? "· " : ""), o[i], n[o[i]]; print "" }' "$FIX/cut.tsv"
H "$C" --score "$FIX/cut.tsv"
H "$C" --due
