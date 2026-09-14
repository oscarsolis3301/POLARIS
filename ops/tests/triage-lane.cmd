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
  # The contract file exists so the T-049 drift assertions below can pin `--strict` rc 0 on the
  # approved state — without it every state reds on "contract missing" and the rc proves nothing.
  printf '# fixture contract\n' > ops/contracts/fix.md
  printf -- '---\nid: T-1\ntitle: fixture task\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/a.txt\nverify: []\n---\n' > ops/board/ready/T-1.md
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
# --- T-049: the ask three-way (ask-approval.md § 5) — same fixture, three RULES states. ---------
# The `ask` kind is the ONE denial a human can lift; before T-049 the plan gate never consulted it,
# so an approved decision still burned a Builder's whole context discovering it could not write.
TAB="$(printf '\t')"
# 1) a `path` scope over anything the task owns is a wall: full, and the note says exactly why.
printf '%s\n' "src/a.txt${TAB}path${TAB}-${TAB}frozen for the drill" > "$FIX/repo/ops/RULES.tsv"
OUT="$(cd "$FIX/repo" && bash "$KIT" triage 2>&1)"
printf '%s\n' "$OUT" | sed -n 1p
printf '%s\n' "$OUT" | grep -c "^   .*cannot be built as specified"
# 2) an `ask` scope with NO covering approval is the same wall, but the note names the lift. The
# dir/ scope vs the exact owned path also pins the both-directions pattern intersection.
printf '%s\n' "src/${TAB}ask${TAB}-${TAB}human decision, stop-and-ask" > "$FIX/repo/ops/RULES.tsv"
OUT="$(cd "$FIX/repo" && bash "$KIT" triage 2>&1)"
printf '%s\n' "$OUT" | sed -n 1p
printf '%s\n' "$OUT" | grep -c "^   .*get the human's yes before starting"
# ...and the ready gate agrees BEFORE any builder exists: drift names task + owned pattern + scope,
# and --strict reds on it. This is the ARC sequence stopped at step 1.
DR="$(cd "$FIX/repo" && bash "$KIT" drift 2>&1)"
printf '%s\n' "$DR" | grep -c "READY GATE: T-1 owns 'src/a.txt' under ask scope 'src/'"
( cd "$FIX/repo" && bash "$KIT" drift --strict >/dev/null 2>&1 ); echo "strict-rc=$?"
# 3) an approval recorded on the task settles the question: no finding, --strict back to rc 0, and
# triage falls through to ordinary points routing — 1 point, so solo again.
printf -- '---\nid: T-1\ntitle: fixture task\ntype: feature\npoints: 1\nwsjf: 5\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/a.txt\napproved:\n  - src/ — human, 2026-08-04: fixture approval\nverify: []\n---\n' > "$FIX/repo/ops/board/ready/T-1.md"
OUT="$(cd "$FIX/repo" && bash "$KIT" triage 2>&1)"
printf '%s\n' "$OUT" | sed -n 1p
DR="$(cd "$FIX/repo" && bash "$KIT" drift 2>&1)"
printf '%s\n' "$DR" | grep -c 'READY GATE: T-1'
( cd "$FIX/repo" && bash "$KIT" drift --strict >/dev/null 2>&1 ); echo "strict-rc=$?"
# --- T-136: several SMALL tasks price CONTEXTS, not tasks (test-surfaces.md § 8). ----------------
# n>1 used to be `full` unconditionally. A full wave for n tasks opens n+3 cold starts of ~7,300
# tokens EACH before any work happens — two 1-pointers went to seven contexts of setup. Budget:
# 4 tasks / 6 pts / 3 pts each, and the note must STATE the arithmetic it used, so the lane is
# auditable rather than felt — the grep below pins the numbers, not just the word.
# RULES cleared first: the `ask` scope above would gate T-2 (unapproved) and hide the budget path.
printf '# none\n' > "$FIX/repo/ops/RULES.tsv"
printf -- '---\nid: T-2\ntitle: second fixture task\ntype: feature\npoints: 1\nwsjf: 4\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/b.txt\nverify: []\n---\n' > "$FIX/repo/ops/board/ready/T-2.md"
OUT="$(cd "$FIX/repo" && bash "$KIT" triage 2>&1)"
printf '%s\n' "$OUT" | sed -n 1p
printf '%s\n' "$OUT" | grep -c '^   2 tasks · 2 pts ≤ 6 — one context (~7,300 tokens cold start) beats a full wave.s 5 contexts (~36500 tokens)'
# 2) four 2-pointers: each ≤3 and n ≤4, but 8 pts in all — over the budget, and the note names it.
for t in 1 2 3 4; do
  printf -- '---\nid: T-%s\ntitle: fixture task %s\ntype: feature\npoints: 2\nwsjf: 4\nrisk: normal\nowner: null\nbranch: null\nstatus: ready\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - src/%s.txt\nverify: []\n---\n' "$t" "$t" "$t" > "$FIX/repo/ops/board/ready/T-$t.md"
done
OUT="$(cd "$FIX/repo" && bash "$KIT" triage 2>&1)"
printf '%s\n' "$OUT" | sed -n 1p
printf '%s\n' "$OUT" | grep -c '^   4 claimable tasks · 8 pts — over the solo budget (4 tasks / 6 pts / 3 pts each)'
# 3) a lane already building wins over the budget: parallel lanes are the point.
mv "$FIX/repo/ops/board/ready/T-4.md" "$FIX/repo/ops/board/active/T-4.md"
OUT="$(cd "$FIX/repo" && bash "$KIT" triage 2>&1)"
printf '%s\n' "$OUT" | sed -n 1p
printf '%s\n' "$OUT" | grep -c '^   1 task(s) already active — another lane is building'
