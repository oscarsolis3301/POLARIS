# builder-cmds: the builder's small commands that used to cost a round trip (ops/contracts/smooth.md § 5).
# grant refuses from a card's own lane (§ 5.1) · release --to blocked parks an unclaimed ready card and an
# empty feat branch goes with its worktree (§ 5.2) · handoff --hold stops at review/ (§ 5.3) · --no-before
# with no visual: path asks for no capture · approve --plan makes the plan the run's (§ 5.4).
# HERMETIC, the handover-route pattern: a throwaway repo, its own board, the CLI run from INSIDE it. Every
# absolute path is printed as <FIX>, so the bytes are the same on every machine.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt; echo y > src/b.txt; echo z > src/c.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  printf '# fixture contract\n' > ops/contracts/fix.md
) >/dev/null 2>&1
cd "$FIX/repo"
unset CLAUDE_CODE_SESSION_ID   # hermetic: the caller's session never names a fixture lock or marker
FIXR="$(cd "$FIX" && pwd -P)"
P() { sed -e "s#$FIXR#<FIX>#g" -e "s#$FIX#<FIX>#g"; }
mk() { # mk <column> <id> <risk> <owned path>
  printf -- '---\nid: %s\ntitle: fixture %s\ntype: feature\npoints: 1\nwsjf: 5\nrisk: %s\nowner: null\nbranch: null\nstatus: %s\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - %s\nverify: []\n---\n## Notes\n' \
    "$2" "$2" "$3" "$1" "$4" > "ops/board/$1/$2.md"
}
bc() { git rev-list --count refs/heads/polaris/board 2>/dev/null || echo 0; }
mk ready T-G1 normal src/a.txt

echo '--- 1. grant refuses from a card lane — a feat branch, a card worktree folder — and writes nothing'
n0="$(bc)"; s0="$(git status --porcelain | wc -l | tr -d ' ')"
git checkout -q -b feat/T-G1
bash "$KIT" grant T-G1 src/b.txt -m "why" 2>&1 | P; echo "rc ${PIPESTATUS[0]}"
git checkout -q main
mkdir -p .polaris/wt/T-G1/sub
( cd .polaris/wt/T-G1/sub && bash "$KIT" grant T-G1 src/b.txt -m "why" 2>&1 | P; echo "rc ${PIPESTATUS[0]}" )
rm -rf .polaris/wt
printf 'board commits added: %s · tree changed: %s\n' "$(( $(bc) - n0 ))" "$([ "$(git status --porcelain | wc -l | tr -d ' ')" = "$s0" ] && echo no || echo yes)"

echo '--- 2. release --to blocked parks an UNCLAIMED ready card; a release that removes the worktree removes an empty feat branch too'
mk ready T-U1 normal src/b.txt
bash "$KIT" release T-U1 --to blocked -m "waits on the owner" 2>&1 | P
printf 'column: %s · %s · %s\n' "$(ls ops/board/blocked)" "$(grep -E '^(status|owner):' ops/board/blocked/T-U1.md | tr '\n' ' ')" "$(grep -F 'released by' ops/board/blocked/T-U1.md | sed 's/by [^:]*:/by <who>:/')"
printf 'event: %s · commit: %s\n' "$(tail -1 ops/board/EVENTS.ndjson | sed -n 's/.*"ev":"\([a-z-]*\)".*/\1/p')" "$(git log -1 --format=%s refs/heads/polaris/board)"
bash "$KIT" claim T-G1 2>&1 | grep -c '^✅ claimed T-G1'
bash "$KIT" release T-G1 --to ready 2>&1 | P | grep -F 'T-G1 →'
printf 'feat/T-G1 after an empty release: %s\n' "$(git show-ref --verify --quiet refs/heads/feat/T-G1 && echo kept || echo gone)"
bash "$KIT" claim T-G1 2>&1 | grep -c '^✅ claimed T-G1'
( cd .polaris/wt/T-G1 && echo w > src/a.txt && git commit -qam work ) >/dev/null 2>&1
bash "$KIT" release T-G1 --to ready 2>&1 | P | grep -F 'T-G1 →'
printf 'feat/T-G1 after a release with a commit: %s\n' "$(git show-ref --verify --quiet refs/heads/feat/T-G1 && echo kept || echo gone)"
git branch -D feat/T-G1 >/dev/null 2>&1

echo '--- 3. handoff --hold stops at review/ with held: yes and lands nothing; --no-before with no visual: path in the diff asks for no capture'
printf 'visual: web/\nshot: echo\n' > ops/CONVENTIONS.md
git add ops/CONVENTIONS.md >/dev/null 2>&1; git commit -qm conventions >/dev/null 2>&1
mk ready T-H1 normal src/c.txt
bash "$KIT" claim T-H1 >/dev/null 2>&1
( cd .polaris/wt/T-H1 && echo held > src/c.txt && git commit -qam "held work" ) >/dev/null 2>&1
( cd .polaris/wt/T-H1 && bash "$KIT" handoff T-H1 --hold --no-before "nothing on screen to photograph" 2>&1; echo "rc $?" ) | grep -E '^(✅ T-H1|held:|rc |⛔)'
printf 'column: %s · %s · %s\n' "$(ls ops/board/review)" "$(grep -E '^held:' ops/board/review/T-H1.md)" "$(grep -F 'held at handoff' ops/board/review/T-H1.md)"
printf 'events: %s · commit: %s\n' "$(tail -2 ops/board/EVENTS.ndjson | sed -n 's/.*"ev":"\([a-z-]*\)".*/\1/p' | tr '\n' ' ')" "$(git log -1 --format=%s refs/heads/polaris/board)"
printf 'landed on main: %s · shots asked: %s\n' "$(git log --format=%s main | grep -c 'T-H1' || true)" "$(ls .polaris/shots 2>/dev/null | wc -l | tr -d ' ')"
CLAUDE_CODE_SESSION_ID=bc-next bash "$KIT" next 2>&1
rm -f ops/board/ready/T-G1.md
printf 'held alone: %s\n' "$(CLAUDE_CODE_SESSION_ID=bc-next bash "$KIT" next 2>&1 | tr '\n' '|')"
mk review T-H2 normal src/b.txt
printf 'beside a landable card: %s\n' "$(CLAUDE_CODE_SESSION_ID=bc-next bash "$KIT" next 2>&1 | tr '\n' '|')"
rm -f ops/board/review/T-H2.md

echo '--- 4. approve --plan makes the plan the run'"'"'s plan when a session id is set — and only then'
printf -- '---\nid: T-P1\ntitle: fixture T-P1\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nplan: recut\nowner: null\nbranch: null\nstatus: backlog\ncontract: ops/contracts/fix.md\napproved: []\nfiles_owned:\n  - src/d.txt\nverify: []\n---\n## Notes\n' > ops/board/backlog/T-P1.md
mkdir -p .polaris/handover/bc-plan; printf 'old\n' > .polaris/handover/bc-plan/plan
CLAUDE_CODE_SESSION_ID=bc-plan bash "$KIT" approve --plan recut -m "the owner said yes" 2>&1
printf 'marker: %s\n' "$(cat .polaris/handover/bc-plan/plan)"
env -u CLAUDE_CODE_SESSION_ID bash "$KIT" approve --plan recut -m "again" 2>&1
printf 'a plan marker without a session id: %s\n' "$(ls .polaris/handover/*/plan 2>/dev/null | grep -vc /bc-plan/ || true)"

echo '--- 5. pack prints FILES THAT TOUCH YOURS first, only when _card_reach is defined and lists something'
# _card_reach is T-313's (author.sh). Before it lands an exported stand-in plays it; once it lands the
# real one is sourced over the stand-in, and on this fixture it answers the same: one test file names
# kappa, nothing names zeta — so these bytes hold on both sides of that landing.
mkdir -p tests; printf '# covers kappa\n' > tests/test_kappa.sh; echo k > src/kappa.sh; echo q > src/zeta.txt
git add tests src >/dev/null 2>&1; git commit -qm "fixture tests" >/dev/null 2>&1
mk ready T-K1 normal src/kappa.sh
mk ready T-K0 normal src/zeta.txt
first() { bash "$KIT" pack "$1" 2>/dev/null | awk 'NR > 3 && /^(=== |FILES THAT TOUCH)/ { s = 1 } s && /^$/ { exit } s { sub(/  \(.*/, ""); print }'; }
a="$(bash "$KIT" pack T-K0 2>/dev/null)"
printf 'no _card_reach — first section: %s\n' "$(first T-K0)"
_card_reach() { case "$1" in *T-K1.md) printf 'test\ttests/test_kappa.sh\tkappa\n';; esac; }
export -f _card_reach
printf 'nothing listed — pack byte-identical: %s\n' "$([ "$(bash "$KIT" pack T-K0 2>/dev/null)" = "$a" ] && echo yes || echo NO)"
first T-K1
unset -f _card_reach
