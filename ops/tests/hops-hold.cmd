# hops-hold: the layout pass keeps off what a waiting card owns or reads (ops/contracts/tune.md § 6,
# the hold rule). Every path an OPEN card's files_owned or context_files names — backlog, ready,
# active, review, blocked, read off refs/heads/polaris/board — is held for the pass, and a whole
# feature whose moves, importer edits or mention edits would touch one waits for the next pass
# (like the 25-file cut: a smaller one behind it can still fit). A guide a held pattern covers is not
# proposed. A done card holds nothing, and with no board ref at all the pass is what it always was.
#
# The ground is the practice shop (hops_fixture): checkout · billing · profile fit one pass (22
# files); search (8 more) waits on the cap. HERMETIC: a throwaway repo under mktemp -d; the board
# ref is written with plumbing (one index file, never a checkout); the kit's engine is reached as
# `POLARIS_ROOT=<fixture> python kit/ops/index.py`. CRLF from the indexer is stripped.
PY="$(pwd)/kit/ops/index.py"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/shop"
bash -c '. kit/ops/lib/selftest/hops.sh; hops_fixture "$1"' _ "$R" >/dev/null 2>&1
card() { # card <col> <ID> <key> <path>… — put ONE task file on the board ref (it grows card by card)
  col="$1" id="$2" key="$3"; shift 3
  { printf -- '---\nid: %s\ntitle: "a waiting card"\npoints: 2\n%s:\n' "$id" "$key"
    for p in "$@"; do printf '  - %s\n' "$p"; done
    printf 'risk: normal\n---\n## Why\nwaiting\n'; } > "$FIX/card.md"
  blob="$(git -C "$R" hash-object -w "$FIX/card.md")"
  parent="$(git -C "$R" rev-parse -q --verify refs/heads/polaris/board)"
  GIT_INDEX_FILE="$FIX/board.idx" git -C "$R" update-index --add --cacheinfo "100644,$blob,ops/board/$col/$id.md"
  tree="$(GIT_INDEX_FILE="$FIX/board.idx" git -C "$R" write-tree)"
  c="$(git -C "$R" -c user.name=b -c user.email=b@b.test commit-tree "$tree" ${parent:+-p "$parent"} -m "board: $id")"
  git -C "$R" update-ref refs/heads/polaris/board "$c"
}
P() { # P <label> — what --propose moves, feature by feature (its destination folder), plus a check
  out="$(POLARIS_ROOT="$R" python "$PY" hops --propose 2>&1 | tr -d '\r')"
  printf '%s: ' "$1"
  printf '%s\n' "$out" | awk -F'\t' '$1 == "move" { d = $3; sub(/[^\/]*$/, "", d); if (!(d in n)) o[++k] = d; n[d]++ }
    END { if (!k) printf "nothing"; for (i = 1; i <= k; i++) printf "%s%s %d", (i > 1 ? " · " : ""), o[i], n[o[i]]; print "" }'
}
O() { # O — the guides a guides-only pass would write (--owned on an empty plan)
  : > "$FIX/empty.tsv"
  POLARIS_ROOT="$R" python "$PY" hops --owned "$FIX/empty.tsv" 2>&1 | tr -d '\r' | grep '/CLAUDE.md$' | tr '\n' ' '; echo
}

echo '--- 1. no board ref: the pass as it always was'
P propose; printf 'guides: '; O

echo '--- 2. a done card holds nothing'
card done T-1 files_owned src/components/CartLine.tsx src/App.tsx
P propose

echo '--- 3. a ready card owns one checkout file: checkout waits whole, search fits behind it'
card ready T-2 files_owned src/components/CartLine.tsx
P propose
POLARIS_ROOT="$R" python "$PY" hops --propose 2>&1 | tr -d '\r' | grep -c 'CartLine' | sed 's/^/rows naming CartLine: /'

echo '--- 4. a backlog card READS a file that names a billing file: billing waits too'
mkdir -p "$R/docs"; printf 'Billing talks to src/services/billingApi.ts for every invoice.\n' > "$R/docs/billing.md"
( cd "$R" && git add docs/billing.md && git -c user.name=t -c user.email=t@t.test commit -qm 'docs: billing' ) >/dev/null 2>&1
card backlog T-3 context_files docs/billing.md
P propose

fresh() { rm -f "$FIX/board.idx"; git -C "$R" update-ref -d refs/heads/polaris/board; }

echo '--- 5. a fresh board: a review card owns the file that imports every feature — nothing moves'
fresh; card review T-5 files_owned src/App.tsx
P propose

echo '--- 6. a fresh board: a blocked card owns a whole folder — no move touches it, its guide waits'
fresh; card blocked T-4 files_owned src/hooks/
P propose; printf 'guides: '; O
