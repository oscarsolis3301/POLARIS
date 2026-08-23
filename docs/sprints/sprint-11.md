# Sprint 11 — Enforced isolation (6.1.0) (2026-08-23–)

## T-084 — "checkout-guard — deny checkout-mutating git in the shared primary"
points 3 · risk normal · landed db722e3 (2026-08-23) · claimed 2026-08-23
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
points 3 · risk normal · landed 0227366 (2026-08-23) · claimed 2026-08-23
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
points 3 · risk normal · landed 4d9802b (2026-08-23) · claimed 2026-08-23
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
