# drain-default — ops/contracts/stay-on-request.md § 3-4 (T-193): `drain` defaults to `plan` in
# code (no `drain:` key, one leftover in ready/, everything else green → finish rc 0 with the
# caveat line, not a pending one) and `release <ID> --to backlog` also parks an UNCLAIMED ready/
# task, no lock or worktree touched, one board commit.
#
# HERMETIC (ops/contracts/selftest-sharding.md): a throwaway repo under mktemp -d, the CLI run from
# INSIDE it — polaris anchors to the fixture's own primary — so no live-board write can ever red
# this golden. Nothing printed carries a sha, a path, a time or a user.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  printf 'test: true\n' > ops/CONVENTIONS.md
  git add -A; git commit -qm board
  # one leftover, UNCLAIMED, no plan: tag — drain-default is not about triage scope, just the knob
  printf -- '---\nid: FIX-1\npoints: 1\nwsjf: 1\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/fix.txt\nverify: []\n---\n' > ops/board/ready/FIX-1.md
  git add -A; git commit -qm fixture
) >/dev/null 2>&1
cd "$FIX/repo"
echo "== finish — no drain: key, 1 leftover in ready/ =="
OUT="$(bash "$KIT" finish 2>&1)"; RC=$?
echo "rc=$RC"
printf '%s\n' "$OUT" | grep -oE 'finish: (run complete|not done)'
printf '%s\n' "$OUT" | grep -q 'caveat: 1 queued in ready/ under drain: plan' && echo "caveat: yes" || echo "caveat: no"
printf '%s\n' "$OUT" | grep -q '^⛔ pending' && echo "pending: yes" || echo "pending: no"
echo "== release FIX-1 --to backlog -m ... (unclaimed, straight from ready/) =="
BPRE="$(git rev-parse -q --verify refs/heads/polaris/board 2>/dev/null)"; BPRE="${BPRE:-none}"
RRC=0
bash "$KIT" release FIX-1 --to backlog -m "parked: not part of this run" >/dev/null 2>&1 || RRC=$?
echo "rc=$RRC"
[ -f ops/board/backlog/FIX-1.md ] && echo "backlog file: yes" || echo "backlog file: no"
[ -f ops/board/ready/FIX-1.md ] && echo "ready file still there: yes" || echo "ready file still there: no"
grep -qx 'status: backlog' ops/board/backlog/FIX-1.md && echo "status: backlog" || echo "status: WRONG"
grep -qx 'owner: null' ops/board/backlog/FIX-1.md && echo "owner: null" || echo "owner: WRONG"
BPOST="$(git rev-parse -q --verify refs/heads/polaris/board 2>/dev/null)"; BPOST="${BPOST:-none}"
if [ "$BPRE" = "none" ]; then N="$(git rev-list --count "$BPOST" 2>/dev/null)"; else N="$(git rev-list --count "$BPRE..$BPOST" 2>/dev/null)"; fi
echo "board commits made: $N"
[ -d .polaris/wt/FIX-1 ] && echo "worktree: present" || echo "worktree: none"
