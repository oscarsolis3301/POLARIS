# fold-chain — T-308 (ops/contracts/tune.md § 4): `polaris fold <ID> <ID>…` turns a chain of waiting cards
# into ONE chain card. Every refusal of § 4 dies `fold refused: <reason>` with rc 1 and writes nothing
# (board files, EVENTS and the board ref all byte-identical). A good fold keeps C1 in place with the summed
# points, one steps: item per member, the unions, the max value fields and a recomputed wsjf, appends one
# `### Step <i>` block per folded member, rewires every other open card that waited on a folded ID, lands
# in the column the ready gate answers, and is ONE board commit `chore(board): fold <C2>… → <C1>` that one
# `git revert` undoes.
#
# HERMETIC: a throwaway fixture repo under mktemp -d, the CLI run from INSIDE it. No sha/time/path printed.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'git -C "$FIX/repo" worktree remove --force "$FIX/wt" >/dev/null 2>&1; rm -rf "$FIX"' EXIT
R="$FIX/repo"
export HOME="$FIX/home" USERPROFILE="$FIX/home"; mkdir -p "$HOME"
unset CLAUDE_CODE_SESSION_ID POLARIS_ROOT
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  echo v1 > a.dat; git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\n' > ops/CONVENTIONS.md
  printf '# a\n' > ops/contracts/a.md; printf '# b\n' > ops/contracts/b.md
  card() { # card <column> <id> <plan> <points> <depends_on> <owned> [risk] [contract] [extra frontmatter]
    printf -- '---\nid: %s\ntitle: "card %s"\nplan: %s\npoints: %s\nrisk: %s\ncontract: %s\ndepends_on: %s\nfiles_owned:\n  - %s\n%s---\n## Why\nwhy %s\n## Acceptance criteria\n- [ ] %s works\n## Notes\n- note %s\n' \
      "$2" "$2" "$3" "$4" "${7:-normal}" "${8:-ops/contracts/a.md}" "$5" "$6" "${9:-}" "$2" "$2" "$2" > "ops/board/$1/$2.md"
  }
  # the good chain T-1 ← T-2 ← T-3, and two cards outside it that wait on its members
  card ready   T-1 p 2 '[]'     src/1.txt normal ops/contracts/a.md 'value: 5
time_criticality: 3
risk_opportunity: 2
wsjf: 5.00
verify:
  - bash -n a.sh
context_files: [docs/a.md]
approved: []
'
  card backlog T-2 p 3 '[T-1]'  src/2.txt normal ops/contracts/a.md 'value: 8
time_criticality: 1
risk_opportunity: 4
verify: [bash -n b.sh, bash -n a.sh]
'
  card backlog T-3 p 2 '[T-2]'  src/3.txt normal ops/contracts/a.md 'value: 1
time_criticality: 6
risk_opportunity: 1
'
  card backlog T-4 q 1 '[T-3, T-1]' src/4.txt
  card blocked T-5 q 1 '[T-2]'  src/5.txt
  # refusal material
  card ready   T-6 other 1 '[T-1]' src/6.txt
  card ready   T-7 p 4 '[T-1]'  src/7.txt normal ops/contracts/a.md 'steps:
  - 2 one
  - 2 two
'
  card ready   T-8 p 6 '[T-1]'  src/8.txt
  card ready   T-9 p 1 '[T-1]'  src/9.txt high
  card ready   T-10 p 1 '[T-1]' src/10.txt normal ops/contracts/b.md
  card ready   T-11 big 5 '[T-31]' src/11.txt
  card backlog T-12 big 5 '[T-11]' src/12.txt
  card backlog T-13 big 5 '[T-12]' src/13.txt
  card ready   T-14 p 1 '[]'    src/14.txt
  card backlog T-15 p 1 '[T-2]' src/1.txt
  card ready   T-19 c 1 '[]'    src/19.txt
  card active  T-20 c 1 '[T-19]' src/20.txt
  card backlog T-21 c 1 '[T-19, T-20]' src/21.txt
  card ready   T-22 p 1 '[]'    src/22.txt
  card active  T-23 p 1 '[]'    src/11.txt
  card done    T-31 big 1 '[]'  src/31.txt
  git add -A; git commit -qm board
  mkdir -p "$(git rev-parse --git-common-dir)/polaris-locks/T-22"
  bash "$KIT" note T-23 -m "the first board commit"
) >/dev/null 2>&1
cd "$R"
snap() { { cat ops/board/*/*.md ops/board/EVENTS.ndjson; git rev-parse -q --verify refs/heads/polaris/board; } | cksum; }
try() { # try <label> <ids…> — a refusal: its message, its rc, and whether anything was written
  local lb="$1" b out rc; shift; b="$(snap)"
  out="$(bash "$KIT" fold "$@" 2>&1)"; rc=$?
  echo "$lb: rc=$rc"; printf '%s\n' "$out" | sed 's/^/  /'
  [ "$b" = "$(snap)" ] && echo "  nothing written" || echo "  WROTE SOMETHING"
}
echo "--- refusals"
try one-id        T-1
try named-twice   T-1 T-1
try unknown       T-1 T-99
try not-waiting   T-1 T-23
try locked        T-1 T-22
try other-plan    T-1 T-6
try has-steps     T-1 T-7
try over-5        T-1 T-8
try other-risk    T-1 T-9
try other-contract T-1 T-10
try over-13       T-11 T-12 T-13
try unrelated     T-1 T-14
try shared-but-waits T-1 T-15 T-2
try cycle         T-19 T-21
echo "--- a good fold"
B0="$(git rev-parse refs/heads/polaris/board)"
bash "$KIT" fold T-1 T-2 T-3 2>&1; echo "  rc=$?"
echo "board commits added: $(git rev-list --count "$B0"..refs/heads/polaris/board)"
echo "subject: $(git log -1 --format=%s refs/heads/polaris/board)"
echo "fold events: $(grep -c '"ev":"fold","id":"T-1","who":"[^"]*","note":"T-2 T-3"' ops/board/EVENTS.ndjson)"
echo "folded cards left: $(ls ops/board/*/T-2.md ops/board/*/T-3.md 2>/dev/null | wc -l | tr -d ' ')"
echo "survivor (ready/T-1.md):"; sed 's/^/  | /' ops/board/ready/T-1.md
echo "T-4 waits on: $(grep '^depends_on:' ops/board/backlog/T-4.md)"
echo "T-5 waits on: $(grep '^depends_on:' ops/board/blocked/T-5.md)"
echo "T-15 waits on: $(grep '^depends_on:' ops/board/backlog/T-15.md)"
echo "--- one git revert undoes it"
git worktree add -q --detach "$FIX/wt" refs/heads/polaris/board >/dev/null 2>&1
git -C "$FIX/wt" -c user.email=t@t -c user.name=t revert --no-edit HEAD >/dev/null 2>&1; echo "  revert rc=$?"
[ "$(git -C "$FIX/wt" rev-parse 'HEAD^{tree}')" = "$(git rev-parse "$B0^{tree}")" ] \
  && echo "  the board is back, byte for byte" || echo "  THE BOARD DIFFERS"
echo "--- a shared file outside the group sends the survivor to backlog/"
bash "$KIT" fold T-11 T-12 2>&1; echo "  rc=$?"
echo "  T-11 now: $(ls ops/board/*/T-11.md | sed 's#ops/board/##') · $(grep '^points:' ops/board/backlog/T-11.md) · T-13 $(grep '^depends_on:' ops/board/backlog/T-13.md)"
