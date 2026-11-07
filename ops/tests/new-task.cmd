# `polaris new` files drafts as board tasks in ONE command (ops/contracts/task-author.md § 10, T-262).
#
# HERMETIC: a throwaway repo under mktemp -d, the CLI run from INSIDE it, so the live board is never
# read or written. The fixture board holds T-007 in done/, T-009 in review/ owning src/shared.txt and
# T-010 in ready/ owning src/ready.txt, beside a contract, an `ask` rule over src/db/ and a sprint
# header — all on the board ref before the first `new`. Pinned, in order:
#   1. one call, four drafts (the last written from the real TASK.md, its comments kept): the four
#      lines; ONE board commit naming all four; each file's id/status/depends_on and everything else
#      that changed; one event per task; drift clean.
#   2. the ask gate: no approval → backlog with the needs-a-yes line, alone and beside a wait; an
#      approved: entry written in the draft counts.
#   3. ids: a preset free id is kept, a later draft may depend on it, and an assigned id skips past
#      every preset of the call — an earlier blank draft can never take a later draft's preset.
#   4. refusals, one per § 3 line: rc 1, the one ⛔ line, nothing on stdout, the board ref unmoved after
#      each and the board's files identical after all of them. Three stand behind a valid draft (the
#      first check a whole draft passes, a preset taken earlier in the call, the last check), so what
#      is proven is all or nothing — a refusal files none of the drafts, not just the bad one.
# Then, over every call: the drafts byte-identical, SPRINT.md and main untouched, and every success
# line held to the plain-voice bar with plain-voice.cmd's own alternation.
KIT="$(pwd)/kit/ops/polaris"
TPL="$(pwd)/kit/ops/templates/TASK.md"
ALT="$(sed -n "s/.*grep -ciE '\([^']*\)'.*/\1/p" ops/tests/plain-voice.cmd)"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf '# fixture contract\n' > ops/contracts/fix.md
  printf 'src/db/\task\t-\tschema changes wait for a human\n' >> ops/RULES.tsv
  git add -A; git commit -qm board
  printf '# Sprint 1 — fixture\n' > ops/SPRINT.md
  printf -- '---\nid: T-007\ntitle: finished work\npoints: 1\nstatus: done\nfiles_owned:\n  - src/old.txt\n---\n' > ops/board/done/T-007.md
  printf -- '---\nid: T-009\ntitle: waiting to land\npoints: 2\nrisk: normal\nstatus: review\nfiles_owned:\n  - src/shared.txt\ndepends_on: []\n---\n' > ops/board/review/T-009.md
  printf -- '---\nid: T-010\ntitle: ready work\npoints: 1\nrisk: normal\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/ready.txt\ndepends_on: []\n---\n' > ops/board/ready/T-010.md
  # the board ref's first commit, by board_commit's own plumbing (a secondary index, no checkout)
  GIT_INDEX_FILE="$FIX/idx" git read-tree --empty
  { echo ops/SPRINT.md; find ops/board -type f; } | GIT_INDEX_FILE="$FIX/idx" git update-index --add --stdin
  git update-ref refs/heads/polaris/board "$(git commit-tree "$(GIT_INDEX_FILE="$FIX/idx" git write-tree)" -m 'chore(board): fixture')"
  D=.polaris/drafts; mkdir -p "$D"
  printf -- '---\nid:\ntitle: first draft\ntype: feature\nplan: p\npoints: 2\nvalue: 8\ntime_criticality: 5\nrisk_opportunity: 3\nwsjf:\nrisk: normal\nstatus: backlog\nowner: null\nbranch: null\nfiles_owned:\n  - src/a.txt\ndepends_on: []\ncontract: ops/contracts/fix.md\nverify:\n  - true\n---\n## Why\nfixture\n' > "$D/a.md"
  printf -- '---\nid: XXX-000\ntitle: shares a file with work in review\nplan: p\npoints: 1\nrisk: normal\nstatus: backlog\nfiles_owned:\n  - src/shared.txt\ndepends_on:\n  - T-007\n---\n' > "$D/b.md"
  printf -- '---\ntitle: after finished work\nplan: p\npoints: 3\nrisk: high\nfiles_owned:\n  - src/c.txt\ndepends_on: [T-007]\n---\n' > "$D/c.md"
  sed -e 's/^title:.*/title: straight from the template/' -e 's/^points:.*/points: 1/' -e 's/^# plan:.*/plan: p/' \
      -e 's|^  - *# exact path.*|  - src/a.txt|' "$TPL" > "$D/d.md"
  dr() { printf -- '---\nid: %s\ntitle: %s\nplan: p\npoints: %s\nrisk: %s\nfiles_owned:\n%bdepends_on: %s\ncontract: %s\n%b---\n' "$@"; }
  dr '' 'owns the schema' 1 normal '  - src/db/schema.sql\n' '[]' '' '' > "$D/e.md"
  dr '' 'the schema and a shared file' 1 normal '  - src/db/seed.sql\n  - src/shared.txt\n' '[]' '' '' > "$D/f.md"
  dr '' 'already approved' 1 normal '  - src/db/fixtures.sql\n' '[]' '' 'approved:\n  - src/db/ — the owner, 2026-11-07: fixture\n' > "$D/g.md"
  dr '' 'blank before a preset' 1 normal '  - src/i.txt\n' '[]' '' '' > "$D/i.md"
  dr T-050 'a preset free id' 1 normal '  - src/k.txt\n' '[]' '' '' > "$D/k.md"
  dr '' 'depends on the preset' 1 normal '  - src/h.txt\n' '[T-050]' '' '' > "$D/h.md"
  dr '' 'valid' 1 normal '  - src/ok.txt\n' '[]' '' '' > "$D/ok.md"
  dr '' 'too big' 8 normal '  - src/p8.txt\n' '[]' '' '' > "$D/p8.md"
  printf -- '---\ntitle: no plan\n# plan: p\npoints: 1\nrisk: normal\nfiles_owned:\n  - src/np.txt\n---\n' > "$D/noplan.md"
  dr '' 'missing contract' 1 normal '  - src/mc.txt\n' '[]' 'ops/contracts/nope.md' '' > "$D/nocontract.md"
  dr '' 'owns nothing' 1 normal '  -\n' '[]' '' '' > "$D/noown.md"
  dr T-009 'a taken id' 1 normal '  - src/tk.txt\n' '[]' '' '' > "$D/taken.md"
  dr T-060 'a preset' 1 normal '  - src/t60.txt\n' '[]' '' '' > "$D/p60.md"
  dr T-060 'the same preset again' 1 normal '  - src/t60b.txt\n' '[]' '' '' > "$D/p60b.md"
  dr '' 'unknown dependency' 1 normal '  - src/ud.txt\n' '[T-404]' '' '' > "$D/nodep.md"
  dr X-1 'a bad id' 1 normal '  - src/x1.txt\n' '[]' '' '' > "$D/badid.md"
  dr '' 'odd risk' 1 medium '  - src/rk.txt\n' '[]' '' '' > "$D/risk.md"
  dr '' '' 1 normal '  - src/nt.txt\n' '[]' '' '' > "$D/notitle.md"
  printf 'title: no frontmatter\n' > "$D/nofm.md"
  mkdir -p "$FIX/orig"; cp "$D"/*.md "$FIX/orig/"
) >/dev/null 2>&1
cd "$R"
D=.polaris/drafts
cnt() { git rev-list --count refs/heads/polaris/board 2>/dev/null || echo 0; }
fm3() { printf '%s: %s\n' "$1" "$(grep -E '^(id|status|depends_on):' "ops/board/$1.md" | tr '\n' '|')"; }
snap() { { find ops/board -type f | sort | xargs cat; cat ops/SPRINT.md; git rev-parse refs/heads/polaris/board; } | cksum; }
run() { # run <drafts…> — one call: its stdout (kept for the plain-voice bar), then rc + stderr
  local rc=0
  bash "$KIT" new "$@" > "$FIX/out" 2> "$FIX/err" || rc=$?
  cat "$FIX/out"; cat "$FIX/out" >> "$FIX/said"
  printf 'rc=%s stderr=[%s]\n' "$rc" "$(tr '\n' ' ' < "$FIX/err")"
}
refuse() { # refuse <label> <args…> — rc, the ⛔ line, stdout, and whether the board ref moved off $REF0
  local rc=0
  bash "$KIT" new "${@:2}" > "$FIX/out" 2> "$FIX/err" || rc=$?
  printf '%s: rc=%s %s| stdout %s | ref %s\n' "$1" "$rc" "$(tr '\n' ' ' < "$FIX/err")" \
    "$([ -s "$FIX/out" ] && echo PRINTED || echo empty)" \
    "$([ "$REF0" = "$(git rev-parse refs/heads/polaris/board)" ] && echo unmoved || echo MOVED)"
}
BASE0="$(git rev-parse main)"; C0="$(cnt)"
echo "== 1. one call, four drafts"
run "$D/a.md" "$D/b.md" "$D/c.md" "$D/d.md"
echo "board commits: $C0 -> $(cnt)"
git log -1 --format=%s refs/heads/polaris/board
git ls-tree -r --name-only refs/heads/polaris/board | grep -E 'T-01[1-4]\.md$'
for t in ready/T-011 backlog/T-012 ready/T-013 backlog/T-014; do fm3 "$t"; done
echo "-- a.md -> T-011"; diff "$D/a.md" ops/board/ready/T-011.md
echo "-- b.md -> T-012"; diff "$D/b.md" ops/board/backlog/T-012.md
echo "-- c.md -> T-013"; diff "$D/c.md" ops/board/ready/T-013.md
grep '"ev":"new"' ops/board/EVENTS.ndjson | sed -E 's/.*"id":"([^"]*)".*"note":"([^"]*)".*"pts":([0-9]+).*/event new \1 \2 \3/'
bash "$KIT" drift 2>/dev/null
echo "== 2. the ask gate"
run "$D/e.md" "$D/f.md" "$D/g.md"
grep '^  - src/db/ ' ops/board/ready/T-017.md
echo "== 3. ids"
run "$D/i.md" "$D/k.md" "$D/h.md"
git log -1 --format=%s refs/heads/polaris/board
echo "== 4. refusals"
B0="$(snap)"; REF0="$(git rev-parse refs/heads/polaris/board)"
refuse no-argument
refuse no-such-file "$D/missing.md"
refuse in-the-board ops/board/ready/T-010.md
refuse no-frontmatter "$D/nofm.md"
refuse no-title "$D/notitle.md"
refuse points-8 "$D/ok.md" "$D/p8.md"
refuse no-plan "$D/noplan.md"
refuse odd-risk "$D/risk.md"
refuse owns-nothing "$D/noown.md"
refuse missing-contract "$D/nocontract.md"
refuse bad-id "$D/badid.md"
refuse taken-id "$D/taken.md"
refuse taken-in-call "$D/p60.md" "$D/p60b.md"
refuse unknown-dep "$D/ok.md" "$D/nodep.md"
git worktree add -q "$FIX/wt" -b feat/T-099 >/dev/null 2>&1
rc=0; ( cd "$FIX/wt" && bash "$KIT" new "$R/$D/ok.md" > "$FIX/out" 2> "$FIX/err" ) || rc=$?
printf 'feat-worktree: rc=%s %s| stdout %s | ref %s\n' "$rc" "$(tr '\n' ' ' < "$FIX/err")" \
  "$([ -s "$FIX/out" ] && echo PRINTED || echo empty)" \
  "$([ "$REF0" = "$(git rev-parse refs/heads/polaris/board)" ] && echo unmoved || echo MOVED)"
[ "$B0" = "$(snap)" ] && echo "board files after the refusals: identical" || echo "board files after the refusals: CHANGED"
echo "== over every call"
n=0; for f in "$FIX"/orig/*.md; do cmp -s "$f" "$D/${f##*/}" || n=$((n+1)); done; echo "drafts changed: $n"
printf '# Sprint 1 — fixture\n' | cmp -s - ops/SPRINT.md && echo "SPRINT.md untouched" || echo "SPRINT.md CHANGED"
[ "$(git rev-parse main)" = "$BASE0" ] && [ -z "$(git status --porcelain)" ] && echo "main untouched" || echo "main CHANGED"
echo "trade words in the success lines: $(grep -ciE "$ALT" "$FIX/said")"
