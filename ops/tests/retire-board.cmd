# `polaris retire` moves waiting cards aside for their successor in ONE board commit (ops/contracts/smooth.md
# § 2.1-2.2, T-313).
#
# HERMETIC: a throwaway repo under mktemp -d, HOME, USERPROFILE and POLARIS_AWAKE_HOME faked, the CLI run
# from INSIDE it. The fixture board: T-001 done · T-002 backlog (its feat branch holds a commit) · T-003
# ready (its feat branch is empty) · T-004 blocked (its feat branch is checked out in a worktree) · T-005
# active and locked · T-006 in review · T-007 ready, waiting on T-003 · T-008 backlog, waiting on T-002,
# T-004 and T-001 · T-009 ready · T-010 backlog, waiting on T-002. Pinned, in order:
#   1. refusals: rc 1, the one ⛔ line, nothing on stdout, the board ref unmoved after each, and the
#      board's files identical after all of them — one stands behind a valid card, so it is all or nothing.
#   2. --by: the lines, ONE board commit and its subject, the moved files (status, retired_by, the Notes
#      line), the events, T-008 rewired once, T-010 (the successor) loses the wait on its own old card,
#      and both kept branches (one holds a commit, one is checked out).
#   3. --map (a comment, a blank line, a CRLF line): T-007 is rewired to a card not in done/ and so goes
#      back to backlog/ in the same commit; the empty feat/T-003 is removed; the (map) subject.
#   4. status: bare status prints no retired row; --all adds exactly the row and the list.
#   5. a new draft that waits on a retired card is refused at new.
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
export HOME="$FIX/home" USERPROFILE="$FIX/home" POLARIS_AWAKE_HOME="$FIX/awake"
mkdir -p "$HOME" "$POLARIS_AWAKE_HOME"; : > "$POLARIS_AWAKE_HOME/disabled"
unset CLAUDE_CODE_SESSION_ID
KIT="$(pwd)/kit/ops/polaris"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  printf '# Sprint 1 — fixture\n' > ops/SPRINT.md
  t() { # t <col> <ID> <depends_on line(s)> [owner] — one fixture card
    printf -- '---\nid: %s\ntitle: card %s\nplan: p\npoints: 1\nrisk: normal\nstatus: %s\nowner: %s\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/%s.txt\n%b\n---\n## Why\nfixture\n\n## Notes\n' \
      "$2" "$2" "$1" "${4:-null}" "$2" "$3" > "ops/board/$1/$2.md"
  }
  t done T-001 'depends_on: []'
  t backlog T-002 'depends_on: [T-001]'
  t ready T-003 'depends_on: []'
  t blocked T-004 'depends_on: []'
  t active T-005 'depends_on: []' someone
  t review T-006 'depends_on: []'
  t ready T-007 'depends_on: [T-003]'
  t backlog T-008 'depends_on:\n  - T-002\n  - T-004\n  - T-001'
  t ready T-009 'depends_on: []'
  t backlog T-010 'depends_on: [T-002]'
  mkdir -p "$(git rev-parse --git-common-dir)/polaris-locks/T-005"
  GIT_INDEX_FILE="$FIX/idx" git read-tree --empty
  { echo ops/SPRINT.md; find ops/board -type f; } | GIT_INDEX_FILE="$FIX/idx" git update-index --add --stdin
  git update-ref refs/heads/polaris/board "$(git commit-tree "$(GIT_INDEX_FILE="$FIX/idx" git write-tree)" -m 'chore(board): fixture')"
  git branch feat/T-003
  git branch feat/T-002; git update-ref refs/heads/feat/T-002 "$(git commit-tree "$(git rev-parse 'main^{tree}')" -p main -m 'work in progress')"
  git worktree add -q "$FIX/wt4" -b feat/T-004
  mkdir -p .polaris
  printf 'T-003 T-009\n' > .polaris/bad.tsv
  printf '# the re-cut\n\nT-003\tT-009\r\n' > .polaris/map.tsv
  mkdir -p .polaris/drafts
  printf -- '---\ntitle: waits on a retired card\nplan: p\npoints: 1\nrisk: normal\nfiles_owned:\n  - src/late.txt\ndepends_on: [T-002]\n---\n' > .polaris/drafts/late.md
) >/dev/null 2>&1
cd "$R"
cnt() { git rev-list --count refs/heads/polaris/board 2>/dev/null || echo 0; }
snap() { { find ops/board -type f | sort | xargs cat; git rev-parse refs/heads/polaris/board; git branch --format='%(refname)'; } | cksum; }
fm() { printf '%s: %s\n' "$1" "$(grep -E '^(status|retired_by|depends_on):' "ops/board/$1.md" | tr '\n' '|')"; }
refuse() { # refuse <label> <args…> — rc, the ⛔ line, stdout, and whether the board ref moved off $REF0
  local rc=0
  bash "$KIT" retire "${@:2}" > "$FIX/out" 2> "$FIX/err" || rc=$?
  printf '%s: rc=%s %s| stdout %s | ref %s\n' "$1" "$rc" "$(tr '\n' ' ' < "$FIX/err")" \
    "$([ -s "$FIX/out" ] && echo PRINTED || echo empty)" \
    "$([ "$REF0" = "$(git rev-parse refs/heads/polaris/board)" ] && echo unmoved || echo MOVED)"
}
echo "== 1. refusals"
B0="$(snap)"; REF0="$(git rev-parse refs/heads/polaris/board)"
refuse no-argument
refuse by-and-map T-003 --by T-010 --map .polaris/map.tsv -m why
refuse no-successor T-003 -m why
refuse no-why T-003 --by T-010
refuse claimed T-005 --by T-010 -m why
refuse in-review T-006 --by T-010 -m why
refuse in-done T-001 --by T-010 -m why
refuse unknown T-404 --by T-010 -m why
refuse unknown-successor T-003 --by T-404 -m why
refuse retired-too T-003 T-010 --by T-010 -m why
refuse named-twice T-003 T-003 --by T-010 -m why
refuse behind-a-valid T-003 T-006 --by T-010 -m why
refuse bad-map --map .polaris/bad.tsv -m why
refuse no-map --map .polaris/none.tsv -m why
rc=0; ( cd "$FIX/wt4" && bash "$KIT" retire T-003 --by T-010 -m why > "$FIX/out" 2> "$FIX/err" ) || rc=$?
printf 'feat-worktree: rc=%s %s| stdout %s | ref %s\n' "$rc" "$(tr '\n' ' ' < "$FIX/err")" \
  "$([ -s "$FIX/out" ] && echo PRINTED || echo empty)" \
  "$([ "$REF0" = "$(git rev-parse refs/heads/polaris/board)" ] && echo unmoved || echo MOVED)"
[ "$B0" = "$(snap)" ] && echo "board files after the refusals: identical" || echo "board files after the refusals: CHANGED"
echo "== 2. --by"
C0="$(cnt)"
bash "$KIT" retire T-002 T-004 --by T-010 -m "the plan was re-cut" 2>&1
echo "board commits: $C0 -> $(cnt)"
git log -1 --format=%s refs/heads/polaris/board
git ls-tree -r --name-only refs/heads/polaris/board | grep '/retired/'
for x in retired/T-002 retired/T-004 backlog/T-008 backlog/T-010; do fm "$x"; done
tail -1 ops/board/retired/T-002.md
grep '"ev":"retire"' ops/board/EVENTS.ndjson | sed -E 's/.*"id":"([^"]*)".*"note":"([^"]*)".*/event retire \1 \2/'
for b in T-002 T-004; do git show-ref -q --verify "refs/heads/feat/$b" && echo "feat/$b kept" || echo "feat/$b REMOVED"; done
echo "== 3. --map"
C0="$(cnt)"
bash "$KIT" retire --map .polaris/map.tsv -m "map cut" 2>&1
echo "board commits: $C0 -> $(cnt)"
git log -1 --format=%s refs/heads/polaris/board
for x in retired/T-003 backlog/T-007; do fm "$x"; done
[ -e ops/board/ready/T-007.md ] && echo "T-007 still in ready/" || echo "T-007 left ready/"
git show-ref -q --verify refs/heads/feat/T-003 && echo "feat/T-003 KEPT" || echo "feat/T-003 removed (it held no commits)"
echo "== 4. status"
age() { sed -E 's/lock age [0-9]+s/lock age Ns/'; }   # a lock with no meta reads its age off the clock
bash "$KIT" status 2>/dev/null | age > "$FIX/st"; bash "$KIT" status --all 2>/dev/null | age > "$FIX/sta"
cat "$FIX/st"
echo "-- what --all adds:"
diff "$FIX/st" "$FIX/sta"
echo "== 5. new refuses a wait on a retired card"
rc=0; bash "$KIT" new .polaris/drafts/late.md > "$FIX/out" 2> "$FIX/err" || rc=$?
printf 'rc=%s %s| stdout %s\n' "$rc" "$(tr '\n' ' ' < "$FIX/err")" "$([ -s "$FIX/out" ] && echo PRINTED || echo empty)"
