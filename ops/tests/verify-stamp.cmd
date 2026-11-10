# verify-stamp — a skipped check rests on a real proof (minutes.md § 12, correcting § 7).
#
# A green verify leaves .polaris/verify-stamp/<ID> = `<sha> <crc>-<bytes>`: the commit it proved and
# a cksum of the verify list as fm_list prints it. handoff and run-verify skip the checks only when
# BOTH still match; the same code under an edited list is not proven, and neither is a tree no green
# verify ever stamped. The seven cases of § 12, in the order the lane walks them — (3) comes before
# (2) because a refused handoff leaves the task in active/, where the proven handoff can follow:
# (1) the stamp's shape · (3) an edited list makes handoff run the checks and refuse on the red line ·
# (2) the list put back → handoff says proven · (4) run-verify on a same-tree land with that stamp
# skips · (5) no stamp, or an old one-field stamp → the checks run · (6) the list edited to a red
# line → run-verify fails and shows it · (7) `done` removes the stamp.
#
# HERMETIC (the self-land-finish pattern): ONE throwaway repo under mktemp -d, no remote, no session
# id, HOME and USERPROFILE faked together, the CLI run from INSIDE the fixture so polaris anchors to
# it, `landing: integrator` so handoff stops at review/. Nothing printed carries a sha, a path or a date.
unset CLAUDE_CODE_SESSION_ID
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/home"
export HOME="$FIX/home" USERPROFILE="$FIX/home"
export POLARIS_AWAKE_HOME="$FIX/awake-home"
R="$FIX/repo"
( set -e
  git init -q -b main "$R" 2>/dev/null || { git init -q "$R"; git -C "$R" symbolic-ref HEAD refs/heads/main; }
  cd "$R"
  git config user.email t@t; git config user.name t; git config core.autocrlf false
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'base: main\nlanding: integrator\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  printf '# SPRINT 1 — one lane  capacity: 5\n' > ops/SPRINT.md
  printf -- '---\nid: T-1\ntitle: one lane\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/a.txt\nverify:\n  - grep -q y src/a.txt\n---\n## Why\nthe one lane.\n' > ops/board/ready/T-1.md
) >/dev/null 2>&1
cd "$R"
ST=.polaris/verify-stamp/T-1
col() { for c in backlog ready active review done blocked; do [ -f "ops/board/$c/$1.md" ] && { echo "$c"; return; }; done; echo none; }
lsum() { set -- $(printf '%s\n' "$1" | cksum); printf '%s-%s' "$1" "$2"; }   # the listsum of a one-line list
red() { sed -i.bak 's|^  - grep -q y src/a.txt$|  - echo VS-BOOM \&\& false|' "$1" && rm -f "$1.bak"; }
green() { sed -i.bak 's|^  - echo VS-BOOM && false$|  - grep -q y src/a.txt|' "$1" && rm -f "$1.bak"; }

echo '== 1. a green verify stamps <sha> <crc>-<bytes> =='
bash "$KIT" claim T-1 >/dev/null 2>&1; echo "claim rc=$?"
W="$R/.polaris/wt/T-1"
( cd "$W" && echo y > src/a.txt && git commit -qam 'feat: T-1 the edit' ) >/dev/null 2>&1
( cd "$W" && bash "$KIT" verify T-1 >/dev/null 2>&1 ); echo "verify rc=$?"
echo "stamp lines: $(grep -c . "$ST" 2>/dev/null || echo 0)"
[ "$(cat "$ST" 2>/dev/null)" = "$(git -C "$W" rev-parse HEAD) $(lsum 'grep -q y src/a.txt')" ] && echo 'stamp is <HEAD sha> <crc>-<bytes>: yes' || echo 'stamp is <HEAD sha> <crc>-<bytes>: NO'

echo '== 3. the verify list edited by hand after the stamp: handoff runs it again, and refuses the red line =='
red ops/board/active/T-1.md
OUT="$(cd "$W" && bash "$KIT" handoff T-1 2>&1)"; echo "handoff rc=$?"
echo "said proven: $(printf '%s\n' "$OUT" | grep -c 'verify: proven at' || true)"
printf '%s\n' "$OUT" | grep -q 'VS-BOOM' && echo 'showed the red line: yes' || echo 'showed the red line: NO'
echo "T-1 is in: $(col T-1)"

echo '== 2. the list put back: handoff says proven and does not re-run =='
green ops/board/active/T-1.md
OUT="$(cd "$W" && bash "$KIT" handoff T-1 2>&1)"; echo "handoff rc=$?"
echo "said proven, not re-run: $(printf '%s\n' "$OUT" | grep -c '^✅ verify: proven at [0-9a-f]\{7\} — not re-run$' || true)"
echo "verify lines re-run: $(printf '%s\n' "$OUT" | grep -c 'verify\[1\]: ' || true)"
echo "T-1 is in: $(col T-1)"

echo '== 4. run-verify on a same-tree land, with a matching stamp: skipped =='
( git checkout -q -b integrate/vs main && git merge -q --squash feat/T-1 && git commit -qm 'land T-1 [T-1]' ) >/dev/null 2>&1
bash "$KIT" run-verify T-1 2>&1; echo "run-verify rc=$?"

echo '== 5. same tree, no stamp (or an old one-field stamp): the checks run =='
mv "$ST" "$FIX/stamp"
bash "$KIT" run-verify T-1 2>&1; echo "run-verify rc=$?"
cut -d' ' -f1 "$FIX/stamp" > "$ST"
bash "$KIT" run-verify T-1 2>&1; echo "run-verify rc=$?"
mv "$FIX/stamp" "$ST"

echo '== 6. same tree and stamp, the list edited to a red line: run-verify fails and shows it =='
red ops/board/review/T-1.md
OUT="$(bash "$KIT" run-verify T-1 2>&1)"; echo "run-verify rc=$?"
echo "skipped: $(printf '%s\n' "$OUT" | grep -c 'not re-run' || true)"
printf '%s\n' "$OUT" | grep -q 'VS-BOOM' && echo 'showed the red line: yes' || echo 'showed the red line: NO'
green ops/board/review/T-1.md

echo '== 7. done removes the stamp =='
( git checkout -q main && git merge -q --ff-only feat/T-1 ) >/dev/null 2>&1
echo "stamp before done: $([ -f "$ST" ] && echo yes || echo no)"
bash "$KIT" done T-1 >/dev/null 2>&1; echo "done rc=$?"
echo "T-1 is in: $(col T-1)"
echo "stamp after done: $([ -f "$ST" ] && echo yes || echo no)"
