# hops-pass: one layout pass as `polaris hops` sees it, from its worktree to its land
# (ops/contracts/save-hops.md § 12.1-§ 12.3). The first real pass, on this very shop, was misread
# three ways: from its worktree, its own branch and its own staged edits counted as somebody else's
# work in progress, so every file it moved was frozen — no guides offered for the new folders, and
# the wrong after-score; after `done` its kept branch froze the same files on main until a sweep;
# and its land commit, under the 40-path skip, counted as one ordinary change that tied every
# feature together through src/App.tsx (and read 1.34 where the moves made 1.31), so the cluster
# it left behind was never proposed again. Here the pass is walked again, the way the 6.12.0 one
# went: the first 25 MOVE rows (one pass's cap) — checkout, billing, profile and three of search's
# eight files.
#   1. main before the pass: --score says the plan takes 2.80 folders per change to 1.31.
#   2. the worktree, moves committed (and pushed), importers fixed but only staged: --tsv counts
#      every moved file where it now lives and asks for a guide in each new folder of 5+ files.
#   3. the pass commits, writes those guides, commits again: line 1 says the 1.31 --score promised.
#   4. the land: ONE squash commit on main with the LAYOUT.tsv rows in it, T-1 in done/ on the board
#      ref, feat/T-1 kept here and on origin.
#   5. main reads exactly what the worktree read, and the five search files left behind keep their
#      MOVE rows. The guides' headings show the purpose rule: `<dir>/ — ` goes once, and only when
#      text follows it.
#   6. a task that is NOT finished still holds the file it changes, seen from the worktree too.
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

echo '--- 1. main before the pass: the plan is the first 25 MOVE rows'
mkdir -p "$R/.polaris"
H "$R" --tsv | awk -F'\t' '$1 == "MOVE" && n++ < 25 { print "move\t" $2 "\t" $3 }' > "$P"
H "$R" --score "$P"

echo '--- 2. the worktree: moves committed, importers fixed and staged'
( cd "$R" && git worktree add -q "$WT" -b feat/T-1 && cd "$WT" \
  && mkdir -p src/checkout src/billing src/profile src/search \
  && for h in checkout billing profile search; do
       git mv $(awk -F'\t' -v h="src/$h/" 'index($3, h) == 1 { print $2 }' "$P") "src/$h/" || exit 1
     done \
  && git commit -qm 'layout: 25 files into their feature folders' \
  && git update-ref refs/remotes/origin/feat/T-1 HEAD \
  && python - "$P" <<'FIXUP' && git add -A
# every @/ import of a moved file follows it, and LAYOUT.tsv records each move
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
) >/dev/null 2>&1
TSV="$(H "$WT" --tsv)"
printf '%s\n' "$TSV"
printf '%s\n' "$TSV" | awk -F'\t' '$1 == "MAP" && $2 ~ /^src\/(checkout|billing|profile|search)\/$/ { n += $3 }
  END { printf "moved files counted where they now live: %d of 25\n", n }'

echo '--- 3. the pass commits, writes the guides --tsv asked for, commits: bare hops, line 1'
( cd "$WT" && git commit -qm 'layout: every import follows its file' \
  && printf '<!-- polaris:guide -->\n# src/checkout/ — the cart, its coupons and tax, and the pay button\n<!-- /polaris:guide -->\n' > src/checkout/CLAUDE.md \
  && printf '<!-- polaris:guide -->\n# src/billing/ — src/billing/ — invoices and the card on file\n<!-- /polaris:guide -->\n' > src/billing/CLAUDE.md \
  && printf '<!-- polaris:guide -->\n# src/profile/ — \n<!-- /polaris:guide -->\n' > src/profile/CLAUDE.md \
  && git add -A && git commit -qm 'layout: a guide for each new folder' ) >/dev/null 2>&1
L1="$(H "$WT" | sed -n 1p)"
printf '%s\n' "$L1"

echo '--- 4. the land: one commit on main, T-1 done on the board, its branch kept'
( cd "$R" && git merge -q --squash feat/T-1 && git commit -qm 'T-1: one layout pass' ) >/dev/null 2>&1
printf 'commit refs/heads/polaris/board\ncommitter Board <board@fixture-shop.test> 1767225600 +0000\ndata <<EOF\nboard: T-1 done\nEOF\nM 100644 inline ops/board/done/T-1.md\ndata <<EOF\n# T-1 one layout pass\nEOF\n\n' \
  | git -C "$R" fast-import --quiet >/dev/null 2>&1
git -C "$R" log -1 -M --name-status --format= main | awk -F'\t' 'NF > 1 { n++; if ($NF == "ops/LAYOUT.tsv") l = 1 }
  END { printf "land: one commit of %d paths, ops/LAYOUT.tsv %s\n", n, l ? "among them" : "not among them" }'
printf 'board: %s · kept: %s\n' "$(git -C "$R" ls-tree --name-only refs/heads/polaris/board -- ops/board/done/)" \
  "$(git -C "$R" for-each-ref --format='%(refname:short)' refs/heads/feat/ refs/remotes/origin/feat/ | awk '{ printf "%s%s", s, $0; s = " " }')"

echo '--- 5. main after the land: the same line 1, and the cluster left behind keeps its MOVE rows'
M1="$(H "$R" | sed -n 1p)"
printf '%s\n' "$M1"
[ "$M1" = "$L1" ] && echo 'line 1 on main = line 1 in the worktree' || echo 'line 1 on main differs from the worktree'
H "$R" --tsv

echo '--- 6. an unfinished task holds what it changes, even seen from the worktree'
( cd "$R" && git checkout -qb feat/T-2 && printf '// wip\n' >> src/hooks/useSearch.ts \
  && git commit -qam 'search: wip' && git checkout -q main ) >/dev/null 2>&1
H "$WT" --tsv | awk -F'\t' '$1 == "MOVE" { n++; if ($2 == "src/hooks/useSearch.ts") h = 1 }
  END { printf "MOVE rows: %d · src/hooks/useSearch.ts among them: %s\n", n, h ? "yes" : "no" }'
