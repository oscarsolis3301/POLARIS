# self-land-finish — one lane, start to finish, ends green with no hand clean-up (minutes.md § 7, § 11.2).
#
# The two sprints before 6.14.0 both ended with somebody tidying by hand after a self-landed lane:
# `finish` named the merged integrate/<date> as a caveat, and the doc-overflow findings reddened qa.
# This walks the whole lane under `landing: self` — claim → edit → verify → handoff, whose tail takes
# the lease, lands, seals and finishes the task — then `finish`, with no `sweep` and no git by hand.
# Pinned: verify stamps the commit and handoff says it did not re-run the checks · the task is in
# done/ · `finish` exits 0, says it cleaned the merged wave branch, and no integrate/* is left ·
# a Learned list over the limit is an advisory line and never a red finish · run-verify on the very
# tree the builder proved says so and runs nothing.
#
# HERMETIC (the seal-fallback pattern): ONE throwaway repo under mktemp -d, no remote, no session id,
# HOME and USERPROFILE faked together, the CLI run from INSIDE the fixture so polaris anchors to it.
# Nothing printed carries a sha, a path, a date or a user.
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
  printf 'base: main\nlanding: self\n' > ops/CONVENTIONS.md
  printf '# fixture contract\n' > ops/contracts/fix.md
  git add -A; git commit -qm board
  printf '# SPRINT 1 — one lane  capacity: 5\n' > ops/SPRINT.md
  printf -- '---\nid: T-1\ntitle: one lane\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/a.txt\nverify:\n  - grep -q y src/a.txt\n---\n## Why\nthe one lane.\n' > ops/board/ready/T-1.md
) >/dev/null 2>&1
cd "$R"
col() { for c in backlog ready active review done blocked; do [ -f "ops/board/$c/$1.md" ] && { echo "$c"; return; }; done; echo none; }

echo '== 1. claim, edit, verify: a green verify stamps the commit =='
bash "$KIT" claim T-1 >/dev/null 2>&1; echo "claim rc=$?"
W="$R/.polaris/wt/T-1"
( cd "$W" && echo y > src/a.txt && git commit -qam 'feat: T-1 the edit' ) >/dev/null 2>&1
( cd "$W" && bash "$KIT" verify T-1 >/dev/null 2>&1 ); echo "verify rc=$?"
[ "$(tr -d ' \r\n' < .polaris/verify-stamp/T-1 2>/dev/null)" = "$(git -C "$W" rev-parse HEAD)" ] && echo 'stamp names the commit: yes' || echo 'stamp names the commit: NO'

echo '== 2. handoff: the checks are not re-run, and the lane lands itself =='
OUT="$(cd "$W" && bash "$KIT" handoff T-1 2>&1)"; echo "handoff rc=$?"
echo "said proven, not re-run: $(printf '%s\n' "$OUT" | grep -c '^✅ verify: proven at [0-9a-f]\{7\} — not re-run$' || true)"
echo "verify lines re-run: $(printf '%s\n' "$OUT" | grep -c 'verify\[1\]: ' || true)"
echo "T-1 is in: $(col T-1)"

echo '== 3. run-verify on the very tree the builder proved runs nothing; another tree runs the lines =='
( cd "$W" && bash "$KIT" run-verify T-1 2>&1 ); echo "run-verify rc=$?"
bash "$KIT" run-verify T-1 2>&1; echo "run-verify rc=$?"

echo '== 4. a Learned list over the limit is advice, never a red finding =='
{ printf '# SPRINT 1 — one lane  capacity: 5\n\n## Learned\n'; i=0; while [ "$i" -lt 9 ]; do i=$((i+1)); printf -- '- lesson %s\n' "$i"; done; } > ops/SPRINT.md
OUT="$(bash "$KIT" drift --strict 2>&1)"; echo "drift --strict rc=$?"
printf '%s\n' "$OUT" | grep -E '^   advisory: LEARNED: '
echo "counted findings: $(printf '%s\n' "$OUT" | grep -c '^⚠' || true)"

echo '== 5. finish: green, and the lane left nothing behind for anyone to clear =='
OUT="$(bash "$KIT" finish 2>&1)"; echo "finish rc=$?"
printf '%s\n' "$OUT" | grep -E '^   cleaned: integrate/' | sed -E 's#integrate/[0-9-]+#integrate/<date>#'
echo "pending: $(printf '%s\n' "$OUT" | grep -c '^⛔ pending' || true)"
echo "caveats: $(printf '%s\n' "$OUT" | grep -c '^   caveat: ' || true)"
printf '%s\n' "$OUT" | grep -oE 'finish: run complete'
echo "integrate branches left: $(git for-each-ref --format='%(refname:short)' 'refs/heads/integrate/*' | grep -c . || true)"
echo "task worktrees left: $(git worktree list --porcelain | grep -c '^worktree .*/.polaris/wt/' || true)"
echo "feat branches left: $(git for-each-ref --format='%(refname:short)' 'refs/heads/feat/*' | grep -c . || true)"
