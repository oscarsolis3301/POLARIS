# `triage` is the ROUTER: CLAUDE.md sends every `start` and every unprompted work request through
# it and takes line 1 as the lane. That makes its output load-bearing — a crash, an extra line, or
# a changed first word silently misroutes every session in the repo.
#
# HERMETIC since T-062. The first golden ran triage against the LIVE board, so ANY session filing
# a task flipped line 1 — T-064's filing turned the pinned `full` into `solo`, red on main, sealed
# without kickback; under N chats it went red every time anyone touched ready/. So this .cmd now
# builds its own fixture board in a throwaway repo and runs the CLI from INSIDE it — polaris
# anchors to the worktree-list primary, which becomes the fixture — and live-board writes can
# never red it again. Running it twice from ANY board state is byte-identical.
#
# ONE triage invocation, reused (the 5.21.0 lesson): ~0.7s of startup per call is real money in a
# suite that runs on every check.
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
  git add -A; git commit -qm board
  # ONE claimable 1-point normal-risk task, no knobs set, nothing RULES-guarded → the SOLO lane,
  # with exactly one three-space note line under it. Every branch of the answer is fixture-pinned.
  printf -- '---\nid: T-1\ntitle: fixture task\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\nfiles_owned:\n  - src/a.txt\nverify: []\n---\n' > ops/board/ready/T-1.md
) >/dev/null 2>&1
OUT="$(cd "$FIX/repo" && bash "$KIT" triage 2>&1)"
# Line 1 must be EXACTLY one bare word, always — reasons go on `   ` note lines below it, so a
# caller can branch on line 1 without parsing.
printf '%s\n' "$OUT" | sed -n '1p'
printf '%s\n' "$OUT" | sed -n '1p' | grep -cE '^(solo|express|full)$'
printf '%s\n' "$OUT" | sed -n '2,$p' | grep -c '^   '
# The SOLO envelope. 5.21.0 widened it 2 -> 3 points because the gates were never the expense, the
# CONTEXTS were: a 3-point task in `express` opens three cold starts to land work one context
# finishes. This asserts the threshold ITSELF, not the help text — a revert to 2 reds here.
grep -c 'pts" -le 3 \]' kit/ops/lib/observe.sh
# ...and the help text must agree with it. cli-docs-parity: one fact, one home — a threshold that
# disagrees with its own documentation is how an agent talks itself back into the wrong lane.
bash kit/ops/polaris help | grep -c '1 task ≤3pts'
