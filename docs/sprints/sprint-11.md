# Sprint 11 — Enforced isolation (6.1.0) (2026-08-23–)

## T-084 — "checkout-guard — deny checkout-mutating git in the shared primary"
points 3 · risk normal · landed db722e3 (2026-08-23) · claimed 2026-08-23 → done 2026-08-23
files touched: kit/.claude/settings.json, kit/ops/hooks/checkout-guard.sh, kit/ops/install.sh

### Why
Five parallel sessions share ONE primary checkout, and today any of them can `git switch` it out
from under the others — that is exactly how one PR silently carried another session's commits.
This task ships the guard that makes the primary untouchable: a new PreToolUse Bash hook that
DENIES checkout-mutating git commands (`switch`, `checkout`, `reset`, `stash`, `merge`, `rebase`,
`cherry-pick`, `worktree add`, `branch -D/-d/-m/-M`) when the session's cwd is the primary
worktree, and stays silent (allow) inside a task worktree `.polaris/wt/<ID>` or for read-only
git. Contract § v2.1 pins the deny message, the detection rule (a `/.polaris/wt/` path segment in
cwd means worktree; otherwise primary), and the exact top-level fn names. Register the hook in
the kit settings template and add it to install.sh's chmod line — the settings hook-merge repair
picks it up by path identity on `update` with no merge-code change.

### Acceptance
- [ ] pure bash, no fork to ops/polaris, no python — the readonly-allow timeout lesson (slow
- [ ] every deny command form from contract § v2.1 is refused in the primary; the same commands
- [ ] deny is the PreToolUse JSON permissionDecision shape ownership-guard already emits, and the
- [ ] top-level fns are EXACTLY deny · jstr · mutating_git (api-kit pins — T-086 writes the
- [ ] kit/.claude/settings.json registers it beside ownership-guard (matcher Bash, sane timeout);
- [ ] kit/ops/install.sh:106 chmod line gains ops/hooks/checkout-guard.sh
- [ ] NOT wired into readonly-allow.sh — that hook only ever ALLOWS, by contract

## T-085 — "ownership-guard learns the primary — no gate-free writes while lanes run"
points 3 · risk normal · landed 0227366 (2026-08-23) · claimed 2026-08-23 → done 2026-08-23
files touched: kit/ops/hooks/ownership-guard.sh

### Why
The write-guard keys ownership off the CURRENT DIRECTORY'S branch (`feat/*` = task, anything
else = no gate at all). A session that never entered its worktree sits in the primary on `main`
with the ownership system fully disengaged — the exact state five colliding sessions were in.
Add `primary_gate`, called before the existing branch-keyed path: when cwd is the primary
worktree AND HEAD is not `feat/*` AND at least one task lock dir exists under polaris-locks
(ignore `.int-lease` and the board mutex), deny writes to tracked source paths with the
contract's pinned remedy line. Allowlist first: `ops/board/`, `ops/contracts/`, `ops/*.md`,
`.polaris/`, untracked paths — a PLANNER or INTEGRATOR in the primary keeps working normally.
No locks (INIT, lone planner, empty board) = no gate: accepted trade, recorded in contract § v2.2.

### Acceptance
- [ ] primary + planted lock + HEAD main + tracked source path (e.g. kit/ops/polaris) → deny
- [ ] same payload but path under ops/board/ or ops/contracts/ or ops/*.md or .polaris/ → allow
- [ ] no lock dirs (or only .int-lease/board-mutex) → allow; cwd inside .polaris/wt/<ID> →
- [ ] non-repo / unreadable cwd → fail OPEN (allow), like every other error path in this hook
- [ ] exactly ONE new top-level fn: primary_gate (api-kit pin; cleanup/jstr/lc/norm stay)
- [ ] existing behavior on feat/* branches byte-for-byte unchanged
- [ ] stays within the hook's configured timeout — no new subprocess storms (the guard once

## T-086 — "Invariant 2 becomes true — claim sweeps ready ∪ active, drift --strict fails overlap"
points 3 · risk normal · landed 4d9802b (2026-08-23) · claimed 2026-08-23 → done 2026-08-23
files touched: kit/ops/lib/builder.sh, kit/ops/lib/observe.sh, ops/tests/api-kit.expected

### Why
Invariant 2 says no two claimable tasks ever share a file, but nothing enforces it end to end:
the claim-time gate (builder.sh, T-059 loop) compares the candidate only against `active/`, and
`drift` merely REPORTS an OWNERSHIP OVERLAP. Two planners racing can leave overlapping tasks in
`ready/`, and the loser surfaces two builds later as an integrator squash conflict. Extend the
existing loop to also iterate `ready/` (skipping the candidate itself) — same pat_overlap both
directions, same explicit-die vs auto-park-to-blocked/ behavior, message gains the `overlaps
ready` variant pinned in contract § v2.3. In observe.sh, make OWNERSHIP OVERLAP a FAILING finding
under `--strict` (CI already runs drift --strict), leaving plain `drift` output unchanged. This
task is also wave 1's sole owner of ops/tests/api-kit.expected: write EXACTLY the four pinned
additions from contract § v2.3 (three checkout-guard fns + primary_gate), sorted in place — from
the contract, never from the other lanes' diffs.

### Acceptance
- [ ] explicit `claim <ID>` whose files_owned overlaps a READY task dies naming the task and
- [ ] auto-pick claim parks the overlapping candidate in blocked/ with the remedy note and keeps
- [ ] `drift` exit code unchanged without --strict; with --strict an OWNERSHIP OVERLAP finding
- [ ] NO new top-level fns in builder.sh or observe.sh (surface-frozen except the golden)
- [ ] ops/tests/api-kit.expected delta is EXACTLY the 4 contract-pinned lines, sorted in place
- [ ] `bash kit/ops/polaris doctor --selftest` drills claimguard and drift stay green

## T-087 — "Worktree entry is mechanical — claim instructs, fleet and roles carry the step"
points 2 · risk normal · landed 3d6b235 (2026-08-23) · claimed 2026-08-23 → done 2026-08-23
files touched: kit/ops/lib/builder.sh, kit/ops/lib/observe.sh, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/SOLO.md

### Why
Root cause #1 of the collisions: claim creates `.polaris/wt/<ID>` and then only PRINTS
`claimed <ID> → cd "<path>"` — entering the worktree is prose a session can skip, and a session
that skips it works in the shared primary on `main`. Make entry mechanical everywhere the
kickoff is generated — and there are TWO callers (contract v2.4, wave-1 field finding): a
top-level session (the human's ~5-chat workflow, and every fleet pane) enters via
EnterWorktree({path: ".polaris/wt/<ID>"}) with no prompt; a conductor-spawned subagent has its
cwd PINNED at launch and EnterWorktree REFUSES there, so its PRIMARY instruction is absolute
paths under .polaris/wt/<ID> (or cd — the shell's cwd persists between calls). `cmd_claim`
closes with the two contract-pinned lines (the second names both callers); `cmd_fleet` pane
kickoffs carry the EnterWorktree line; `BUILDER.md` step 1b and `SOLO.md` carry BOTH caller
lines; `CONDUCTOR.md`'s builder-kickoff template carries ONLY the subagent form and never
instructs EnterWorktree — an instruction that always fails teaches builders to ignore the step,
the exact failure mode this sprint removes.

### Acceptance
- [ ] claim output ends with BOTH pinned lines, byte-exact per contract v2.4, each on one line
- [ ] fleet's printed/pane kickoff (top-level panes) includes the EnterWorktree line per task
- [ ] BUILDER.md step 1b and SOLO.md carry BOTH caller lines as a numbered step
- [ ] CONDUCTOR.md kickoff template carries the pinned subagent line (absolute paths;
- [ ] the top-level EnterWorktree entry is RE-VERIFIED LIVE before pinning (contract v2.4:
- [ ] no new top-level fns; no new H2 headings in any role file (api-kit records headings)
- [ ] claim/fleet drills stay green (claimguard, fmlist)

## T-088 — "landing: self — a builder queues behind the lease and lands its own task"
points 5 · risk normal · landed 487037e (2026-08-23) · claimed 2026-08-23 → done 2026-08-23
files touched: kit/CLAUDE.md, kit/ops/KEYS.tsv, kit/ops/PROTOCOL.md, kit/ops/lib/builder.sh, kit/ops/lib/observe.sh, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/SOLO.md, ops/tests/api-kit.expected

### Why
Root cause #8 of the collisions: nothing wakes an integrator — handoff prints prose and the
board sits in `review/` forever when no CONDUCTOR runs. The lease already provides "wait your
turn behind the other agents" (int_on: atomic lease, 2s poll, stale steal, queued:/rc 3), so
close the loop: new knob `landing` (KEYS.tsv, since 6.1.0, default `self` IN CODE — the 6.0.0
lesson: update never rewrites CONVENTIONS, so unset must compose to the new behavior). Under
self, cmd_handoff continues into `land <ID>` via ONE new top-level fn `self_land`; the
all-review condition handoff already computes also triggers `seal` (last lane out seals the
wave). HARD STOPS no knob softens: `risk: high` and STOP-AND-ASK tasks never self-land — pinned
refusal, classic integrate notice, today's behavior byte-for-byte (same under
`landing: integrator`). Re-size autolaunch_max 3 to 5 (KEYS row + the code
fallback + CONDUCTOR.md "default 3"); integration_wait_minutes STAYS 10 — human decision
2026-08-23: int_on polls in the FOREGROUND, so a 10-minute bound is already exactly the
harness's 600s tool cap, and a bigger one makes the tool call return nothing and lose the whole
wait. Instead, KEYS.tsv's prose for that key gains the 600s-cap warning (never raise past 10),
and the self-land tail DETACHES: bg run ship-<ID>, collected with chunked bg wait --max 300
(contract v2.5) — the recipe the role files carry. Also reword Invariant 9 in kit/CLAUDE.md with
the human-approved VERBATIM text pinned in contract v2.5 (the lease holder IS the Integrator —
what wave_on always did); replace the existing line 9, touch nothing else in that file. Document self-landing in kit/ops/PROTOCOL.md
section LANES as the SOLO / land --express precedent generalized — edit INSIDE the section, no
new heading. Update BUILDER/SOLO/CONDUCTOR so the builder's life reads claim, build, verify,
handoff, then (self) land.

### Acceptance
- [ ] landing unset or self: handoff of a normal task continues into land; task reaches done/;
- [ ] last lane out (all-review) also seals the wave; mid-wave lands do not seal
- [ ] risk: high NEVER self-lands: pinned ONE-LINE refusal from contract v2.5 + classic
- [ ] self-land runs NO full suite (integration: batch economics unchanged — land is
- [ ] KEYS.tsv gains the landing row; autolaunch_max default 5 everywhere the old default
- [ ] kit/CLAUDE.md invariant 9 replaced with the contract v2.5 verbatim text, byte-exact; no
- [ ] the role files' self-land tail uses bg run ship-<ID> + chunked bg wait --max 300 — never a
- [ ] exactly ONE new top-level fn (self_land, builder.sh); api-kit.expected delta is exactly
- [ ] PROTOCOL section LANES documents self-landing; no new H2 headings anywhere
- [ ] busyint + express + claimguard drills stay green

## T-089 — "Prove it — checkoutguard, readyoverlap, selfland drills + refusal goldens"
points 5 · risk normal · landed 260dfeb (2026-08-23) · claimed 2026-08-23
files touched: kit/ops/lib/selftest/board.sh, kit/ops/lib/selftest/history.sh, kit/ops/lib/selftest/policy.sh, kit/ops/lib/selftest/spine.sh, ops/tests/api-kit.expected, ops/tests/checkout-guard-denies.cmd, ops/tests/checkout-guard-denies.expected, ops/tests/ownership-primary.cmd, ops/tests/ownership-primary.expected

### Why
The three enforcement layers are exactly the kind of behavior prose cannot hold — they must be
drilled or they will silently regress. Add three labeled drills per contract v2.6:
drill_checkoutguard (policy.sh — primary deny + worktree allow + read-only allow, plus
primary_gate: planted lock/no-lock, allowlist, fail-open — AND the fallback entry every
conductor lane actually takes: cwd pinned at the primary, a write via an ABSOLUTE path under
.polaris/wt/<ID> is allowed and the commit lands on feat/<ID>), drill_readyoverlap (board.sh — two
overlapping ready tasks: explicit claim dies with `overlaps ready`, auto-pick parks to blocked/,
drift --strict exits nonzero, plain drift exits zero), drill_selfland (history.sh — unset knob
lands a normal task to done/ through the lease; risk: high stays in review/ with the pinned
refusal; landing: integrator gives the classic notice). Register all three labels at the END of
SELFTEST_LABELS in spine.sh (order: ... route bg checkoutguard readyoverlap selfland). Scaffold
golden pairs (polaris check --scaffold) grepping the two pinned refusal lines out of the hook
scripts themselves — hermetic, no live board. Own the final api-kit.expected delta: the three
drill fns.

### Acceptance
- [ ] all three drills green via --only, each assertion watched RED under a semantic sabotage in
- [ ] checkoutguard asserts the FALLBACK path (contract v2.6): pinned-cwd session, absolute
- [ ] checkoutguard asserts the deny SHAPE: hookSpecificOutput JSON on STDOUT (contract v2.1 —
- [ ] checkoutguard and the goldens assert git stash list / git stash show in the primary are
- [ ] hermetic: git status --porcelain unchanged across each drill; green on a second
- [ ] labels registered; full-run drill count goes 28 to 31; --only selects each individually
- [ ] golden pairs checkout-guard-denies + ownership-primary green via bash ops/polaris check,
- [ ] api-kit.expected delta is exactly drill_checkoutguard + drill_readyoverlap +
- [ ] drill budget respected: about 44s each — reuse the throwaway-repo spine, no new sleeps

## T-091 — "Refresh the cli-help golden — approve + adopt blocks ship on main, the expected file never caught up"
points 1 · risk normal · landed 180bda0 (2026-08-23) · claimed 2026-08-23 → done 2026-08-23
files touched: ops/tests/cli-help.expected

### Why
`bash ops/polaris check` runs 16/17 rc 1 and the sole red is the cli-help golden. Cause is already
diagnosed — do not re-derive it: the `approve` help block ships on main in `kit/ops/polaris` (landed
sprint 10) and reached the installed `ops/polaris` at the 6.0.0 dogfood (fc22a17), but
`ops/tests/cli-help.expected` was never refreshed to match. The first builder's hand-back then
surfaced a SECOND pre-existing gap the `4e9fa63..HEAD` scoping could not see because it predates
that range: the `adopt` help block is also on main and also uncaptured. The Planner re-verified the
FULL delta directly (`bash ops/polaris help | diff - ops/tests/cli-help.expected`, 2026-08-23):
exactly two missing blocks, additions only, no removals, no reorderings, no third gap. Both are
pre-existing on base — wave 1's diff touches neither file. One file, one owner (Invariant 2): both
blocks fold into this one task; a second task owning this golden is exactly what this sprint forbids.
This task re-records the golden so the run closes green.

HOW to refresh: `check --update` is this repo's official golden-refresh mechanism, but `cmd_check`
is PRIMARY-anchored (it reads the primary's `ops/tests/` and runs there — Learned log: a worktree's
golden edits are invisible to it, and `--update` would rewrite the primary, not your branch). So in
the feat/T-091 worktree capture the surface directly — the same operation `--update` performs:
`bash ops/polaris help > ops/tests/cli-help.expected`.
THEN READ THE DIFF before committing: `git diff -- ops/tests/cli-help.expected` must be additions
only, exactly TWO blocks and nothing else:
  1. the `approve <ID> <scope> -m "why"` help block — 5 lines (help output lines ~24-28)
  2. the `adopt` help block — 5 lines (help output lines ~169-173)
10 added lines total; zero removals, zero reordered or changed lines. A golden regenerated without
reading is how a real regression gets locked in as "expected" — anything beyond these two blocks
(a removal, a reordering, a changed line, a THIRD new block) is a finding: STOP and hand back, do
not commit it.

### Acceptance
- [ ] `bash ops/polaris help | diff - ops/tests/cli-help.expected` exits 0 in the worktree
- [ ] the golden's diff vs base is additions only — exactly the approve block (5 lines) plus the
- [ ] post-land (Integrator, on the primary/integrate checkout where primary-anchored check can
