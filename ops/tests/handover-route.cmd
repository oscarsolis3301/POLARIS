# `polaris next` is the ROUTER (ops/contracts/role-handover.md): every role runs it at its boundary
# and follows line 1, and the Stop hook asks it what to do with a session that stopped anyway. Line
# 1 IS the decision — one verb, optionally one ID — so a changed first word misroutes a whole
# session, and a stray line where a caller expects a `   ` note breaks `--brief` and the hook's note
# parsing in the same stroke. Prose cannot hold a decision table; this can.
#
# HERMETIC, the triage-lane pattern (T-062's lesson): the first router golden read the LIVE board
# and went red every time any session filed a task. So this builds its own fixture board in a
# throwaway repo and runs the CLI from INSIDE it — polaris anchors PRIMARY to the worktree-list
# primary, which becomes the fixture — and live-board writes can never red it again.
#
# ONE `next` per board state, reused for all three assertions (the 5.21.0 lesson: ~0.7 s of module
# loading per call is real money in a suite that runs on every check). This is the CHEAP HALF of the
# contract's executable check: the rows a `check` can afford on every run. The rest of the table —
# the lease steal, the avoid list, the hop ladder, `handover: off` — is the `handover` drill's.
# Nothing printed here carries a path, a timestamp, a user name or a version, so the bytes are the
# same on every machine.
KIT="$(pwd)/kit/ops/polaris"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
( set -e
  git init -q -b main "$FIX/repo" 2>/dev/null || { git init -q "$FIX/repo"; git -C "$FIX/repo" symbolic-ref HEAD refs/heads/main; }
  cd "$FIX/repo"
  git config user.email t@t; git config user.name t
  mkdir -p src; echo x > src/a.txt; echo y > src/b.txt
  git add -A; git commit -qm init
  bash "$KIT" init-board
  git add -A; git commit -qm board
  # A real contract file: the promote row holds every candidate to the FULL ready gate, and without
  # one every backlog task fails on "contract missing" and the promote rows would prove nothing.
  printf '# fixture contract\n' > ops/contracts/fix.md
) >/dev/null 2>&1
cd "$FIX/repo"
# A session id is what makes row 0 (my own lock) and the budget row addressable at all: `next` reads
# .polaris/handover/<sid>/, and an unset id resolves to `-`, which matches no lock.
export CLAUDE_CODE_SESSION_ID=hr-sid
L="$(git rev-parse --git-common-dir)/polaris-locks"
mk() { # mk <column> <id> <wsjf> <risk> <owned path>
  printf -- '---\nid: %s\ntitle: fixture %s\ntype: feature\npoints: 1\nwsjf: %s\nrisk: %s\nowner: null\nbranch: null\nstatus: %s\ncontract: ops/contracts/fix.md\nfiles_owned:\n  - %s\nverify: []\n---\n## Notes\n' \
    "$2" "$2" "$3" "$4" "$1" "$5" > "ops/board/$1/$2.md"
}
route() { # one board state, three assertions off ONE invocation: line 1 verbatim · line 1 measured
  # against the CLOSED verb set (a new verb, or a line 1 decorated with anything else, reds here) ·
  # the note count. `next` writes nothing, so each state is exactly what the lines above it built.
  OUT="$(bash "$KIT" next "$@" 2>&1)"
  printf '%s\n' "$OUT" | sed -n 1p
  printf '%s\n' "$OUT" | sed -n 1p | grep -cE '^(resume|build|integrate|promote|wait|stop|finish)( T-[A-Z0-9]+)?$'
  printf '%s\n' "$OUT" | sed -n '2,$p' | grep -c '^   '
  # the promote notes, verbatim minus their indent — the only note text this golden pins, because
  # `--do` is the one verb that CHANGES the board and its report is what the human reads back.
  printf '%s\n' "$OUT" | sed -n 's/^   \(promoted: .*\)$/\1/p;s/^   \(nothing to promote\)$/\1/p;s/^   \(held: .*\)$/\1/p'
}
# --- row 6: an empty board is the run's end, and it says so with NO notes under it. -------------
route
# --- row 3: the only ready task, with its one note. --------------------------------------------
mk ready T-HR1 5 normal src/a.txt
route
# --- row 0: my own live lock on an active task outranks everything — never a second task mid-task.
mv ops/board/ready/T-HR1.md ops/board/active/T-HR1.md
mkdir -p "$L/T-HR1"; printf '%s\nsomeone\nT-HR1\nhr-sid\n-\n' "$(date +%s)" > "$L/T-HR1/meta"
route
rm -rf "$L/T-HR1"; rm -f ops/board/active/T-HR1.md
# --- row 1: landable review work opens the lane. A risk: high task beside it does NOT close the
#     lane — it rides along as a second note naming what only the human may merge. ---------------
mk review T-HR2 5 normal src/b.txt
mk review T-HR3 5 high src/b.txt
route
# --- row 5, the v1.1 correction: human-gated review work ALONE is `wait`, never `finish`. A task
#     waiting on a human IS in flight — with the human — which is why row 6's approval note is
#     unreachable dead source and no case here may assert `finish` for it. ----------------------
rm -f ops/board/review/T-HR2.md
route
rm -f ops/board/review/T-HR3.md
# --- row 4: a backlog task that passes the full ready gate. IDEAS.md carries no frontmatter and
#     must be skipped in silence rather than crashing the scan. -------------------------------
mk backlog T-HR5 5 normal src/a.txt
printf '# not a task\n' > ops/board/backlog/IDEAS.md
route
# --- row 3 OVER row 4, with both live: work already groomed is taken before the board is grown.
#     Swap those two rows and this is the line that reds — the states either side of it cannot see
#     the ordering, because only here are a claimable task and a promotable one both on the board.
mk ready T-HR1 4 normal src/b.txt
route
# --- row 2: the budget stops only what would otherwise START — and here that is BOTH of them. Its
#     note names the CAP KEY, never a number of its own, and counts what is left so the human
#     knows the size of the rest. --------------------------------------------------------------
mkdir -p .polaris/handover/hr-sid; printf '99\n' > .polaris/handover/hr-sid/hops
route
rm -f .polaris/handover/hr-sid/hops ops/board/ready/T-HR1.md
# --- `--do` is the ONE writer: promote under the board lock, then the FRESH route on line 1 (a verb
#     under every flag, so a caller never has to parse), the promote notes, and drift as the audit
#     any board mutation earns. The board effects are asserted from the BOARD, never from prose. --
route --do
ls ops/board/ready
grep -c '"ev":"promote"' ops/board/EVENTS.ndjson
git log -1 --format=%s refs/heads/polaris/board
# --- a second `--do` promotes nothing and says so, still rc 0 and still a verb on line 1: the
#     promoter is idempotent, which is what lets a hopped session run it without checking first. --
route --do
