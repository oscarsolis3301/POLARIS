# Sprint 8 — N chats, one repo (2026-08-03–)

## T-057 — "workspace.sh — id_ok, wt_add, stray-feat repair, the integration lease, wave adoption, park/unpark"
points 5 · risk normal · landed 90b6a46 (2026-08-03) · claimed 2026-08-03 → done 2026-08-03
files touched: kit/ops/lib/core.sh, kit/ops/lib/workspace.sh, kit/ops/polaris, ops/tests/api-kit.expected

### Why
Every "two chats, one repo" failure this plan fixes bottoms out in mechanics no module owns today:
branch IDs are never validated so a stray ref literally named `feat` poisons `worktree add` with the
real error swallowed; six commands die on a dirty tree without naming whose dirt it is; the
integrator path has no concept of "another session holds the lane". This task builds the module that
owns those mechanics — `kit/ops/lib/workspace.sh` — exactly as `ops/contracts/shared-checkout.md`
specifies: `id_ok`, `wt_add` (captured stderr, retry ONLY on real index.lock contention),
`stray_feat_repair` (rename to `stray/feat-<sha7>`, local + origin — archive, never delete),
`int_on`/`int_off` (the integration lease: poll 2s with progress notes, steal only past
`integration_stale_minutes`, rc 3 with one `queued: ` line past `integration_wait_minutes` — never
a question), `wave_on` (create / ff-reuse / ADOPT integrate/<date>), `park`/`unpark` (named stash
`polaris/park-<epoch>`, `--include-untracked`, reversible in one command).

The CLI surface rides along: the loader's FULL-load list gains `workspace` between `ownership` and
`builder` (the `_match|_rules|_guard` short path stays EXACTLY `core ownership` — the write-guard's
latency budget must not pay for this module), dispatch + usage() gain `park`/`unpark`, and core.sh's
`on_die` gains `${INT_HELD:-}`-guarded lease cleanup so a crashed holder never costs 45 minutes.

This task adds this sprint's only non-drill top-level fns, so it also owns the golden that records
the kit surface: hand-author the `ops/tests/api-kit.expected` delta for workspace.sh's fns.

### Acceptance
- [ ] `workspace.sh` defines exactly the contract's fns, ≤350 lines, definitions only (no top-level
- [ ] `id_ok` rejects an empty ID, a bare `feat`, and anything `git check-ref-format` refuses, with
- [ ] `wt_add` never writes `2>/dev/null` on the worktree call: stderr is captured; retry fires only
- [ ] `stray_feat_repair` renames a local branch named `feat` to `stray/feat-<sha7>` and repairs an
- [ ] `int_on` on a free lane takes it instantly; on a busy lane polls 2s with a progress note about
- [ ] `int_on` is re-entrant (already ours → rc 0); `int_off` releases only our own lease
- [ ] `on_die` releases the lease when `INT_HELD` is set; the `_match`/`_rules` guard path is
- [ ] `wave_on` does create / ff-reuse / adopt and SAYS which; the caller-holds-lease precondition
- [ ] `park` stashes tracked + untracked under `polaris/park-<epoch>` and prints a line containing
- [ ] `polaris park` / `polaris unpark` dispatch in `kit/ops/polaris`, documented in usage(), and
- [ ] `ops/tests/api-kit.expected` gains exactly workspace.sh's fn lines (hand-authored, byte-exact

## T-058 — "The integration lane — lease-serialized land/seal/rollback, parked dirt, wave adoption, idempotent re-lands"
points 5 · risk normal · landed 6e5f9b6 (2026-08-03) · claimed 2026-08-03
files touched: kit/ops/lib/integrate.sh, kit/ops/lib/selftest/history.sh

### Why
Integration is where two sessions actually collide: the primary checkout is the only place `land`
and `seal` can run, so today the second integrator dies on the first one's branch state or dirt.
The settled design (shared-checkout v1, pipelined-integration v2): ONE shared lane, serialized by
the lease. This task makes `cmd_land`, `cmd_land_express`, `cmd_seal`, `seal_sync` and
`cmd_rollback` take `int_on` first (rc 3 `queued: ` propagates; `int_off` on every exit), turns
their five dirty-tree dies (integrate.sh:226/296/366/481/572) into `park` + caveat + proceed (park
failure → today's die verbatim, tree untouched), replaces the hand-rolled branch logic with
`wave_on` — `cmd_land` on $BASE creates/adopts instead of dying at :225, express's :298-305 block
goes entirely, deleting the "finish that wave by hand first" die — and makes re-runs idempotent:
an already-landed `land <ID>` prints `already landed — skipped` rc 0, a seal with only board noise
prints `nothing new to seal` rc 0. Two integrators can never die on each other's completed work.
The express drill (selftest/history.sh) updates its assertions to the new step-0 lease + wave_on
lines per express-lane v2.

### Acceptance
- [ ] land / land --express / seal / seal --sync / rollback each acquire the lease before mutating
- [ ] all five dirty-tree die sites park + caveat + proceed; park rc 1 → the old die verbatim,
- [ ] `cmd_land` on $BASE calls wave_on (create / ff-reuse / adopt) instead of dying; express's
- [ ] re-land of an already-landed ID (on the current wave branch or $BASE) → `already landed —
- [ ] seal with only chore(board) subjects → `nothing new to seal`, rc 0 (the :371 die is gone)
- [ ] express-lane v1's four refusals still die BEFORE anything mutates, pinned fragments intact
- [ ] the express drill is green with assertions updated to the new output lines
- [ ] no new top-level function in integrate.sh — inline the glue; call workspace.sh fns directly

## T-059 — "Claim/handoff hardening — id_ok pre-lock, the claim-time disjointness gate, pushes that degrade instead of stranding"
points 5 · risk normal · landed c5d1605 (2026-08-03) · claimed 2026-08-03
files touched: kit/ops/lib/builder.sh, kit/ops/lib/selftest/board.sh, kit/ops/lib/selftest/remote.sh

### Why
A Builder's two worst multi-session failures are both in builder.sh. First, claim: IDs are never
validated (a bad one becomes a bad ref name deep inside `worktree add`) and nothing re-checks
ownership disjointness at claim time, so two planners racing can put overlapping tasks on the board
and the overlap is only discovered as an integrator squash conflict two builds later. Second,
handoff: the push (builder.sh:111) has zero retry and no fallback — one network hiccup strands a
FINISHED task in active/ with its lock held. Per shared-checkout v1: `cmd_claim` runs `id_ok`
BEFORE lock_take and, after locking a candidate, checks its `files_owned` against EVERY active/
task via `pat_overlap` (both directions) — overlap on auto-pick → move the candidate to blocked/
with a ⛔ note naming the active task, both patterns and the remedy, ONE board commit
`chore(board): block <ID> (ownership overlap)`, release its lock, claim the next candidate;
overlap on an explicit ID → die naming the same. `wt_add` replaces the inline retry loop (:62-71)
and cmd_resume's recreate block (:369-371). `cmd_handoff`'s push gets 3 attempts with one
`stray_feat_repair` between them; still failing → PROCEED with the board move (direct-mode landing
merges the LOCAL branch — the work is safe), append the contract's ⚠ push-fail Note to the task,
emit `evt push-fail`, and say so. A finished task is never stranded by the network again.
Claim/handoff assertions live in selftest/board.sh and selftest/remote.sh — update any that the
new claim/handoff output touches (existing drills only; new drills are T-062's).

### Acceptance
- [ ] an invalid ID dies via id_ok BEFORE any lock exists; every historical ID shape still claims
- [ ] the disjointness gate: auto-pick moves the overlapping candidate to blocked/ (note + one
- [ ] a claim with no overlap behaves byte-identically to today (gate is silent when clean)
- [ ] wt_add serves both claim and resume; the old retry loops are gone; a non-index.lock failure
- [ ] handoff push: 3 attempts, one stray-feat repair between, degrade → board move + task Note +
- [ ] existing drills green with updated assertions (grant · remote · syncrace)
- [ ] no new top-level function in builder.sh — inline the glue; call workspace.sh fns directly

## T-060 — "finish/status/doctor/update learn the shared checkout — lease and parks surfaced, update parks instead of dying"
points 3 · risk normal · landed 0cf5945 (2026-08-03) · claimed 2026-08-03
files touched: kit/ops/lib/admin.sh, kit/ops/lib/observe.sh, kit/ops/lib/selftest/policy.sh

### Why
A second chat's first question is "what is going on here?" — and today status/finish cannot answer
it: they know nothing about the integration lease or parked stashes, `finish`'s dirty-tree pending
line names no remedy, and `update` still dies on a dirty configured repo. Per shared-checkout v1:
`cmd_status` gains one line for the lease when held (holder · age) and one per `polaris/park-*`
stash, so the first read explains the world. `cmd_finish` gains a pending line when the lease is
held by another live session, names `park` as the dirty-tree remedy, and lists parked stashes as
caveats (never gates). `cmd_doctor` validates `integration_wait_minutes` /
`integration_stale_minutes` when set (positive integers, one ⚠ line otherwise) and warns once when
git < 2.13 (`stash push`). `cmd_update`'s configured-repo dirty die (admin.sh:359) becomes park +
caveat + proceed (park failure → today's die; the never-configured branch :350-358 is untouched).
finish/hardening drill assertions (selftest/policy.sh) update where output changed.

### Acceptance
- [ ] status shows lease holder + age when held, and each parked stash; silent when neither exists
- [ ] finish: lease held by another session → ⛔ pending naming holder + age; dirty tree pending
- [ ] doctor: bad knob values → one ⚠ line each; unset knobs → silent; git < 2.13 → one warn
- [ ] update on a dirty CONFIGURED repo parks + proceeds + caveat; park failure → today's die;
- [ ] finish + hardening drills green with updated assertions
- [ ] no new top-level function in observe.sh/admin.sh — inline the glue (the api-kit surface

## T-061 — "The sprint-report writer commits its own file when it is the only dirt"
points 2 · risk normal · landed 6dc7ca9 (2026-08-03) · claimed 2026-08-03 → done 2026-08-03
files touched: kit/ops/lib/knowledge.sh, kit/ops/lib/selftest/report.sh

### Why
Contract sprint-report v1.1 documented this failure instead of fixing it: a re-render after `done`
leaves `docs/sprints/sprint-<n>.md` dirty on `<base>`, and the NEXT land/seal dies "working tree not
clean" with no visible cause. In a one-chat world the hint was enough; with N chats, session B pays
for session A's forgotten hint. v2 (this task) kills it at source: after writing, `cmd_report`
SELF-COMMITS its file(s) when — and only when — it runs in the primary checkout, on `$BASE`, and
`git status --porcelain` shows NOTHING but the report file(s) this invocation just wrote. Subjects:
`docs(sprint-<n>): report refresh` (single sprint) · `docs(sprint): report refresh --all` (--all).
Any other dirty path → commit NOTHING, print v1.1's two-remedy hint verbatim, exactly as today.
Seal's own report commit on integrate/<date> is untouched. The `report` drill gains both sides:
only-dirt → commit exists with the pinned subject and the tree is clean; mixed-dirt → no commit,
hint printed.

### Acceptance
- [ ] only-dirt case on $BASE in the primary: report writes, commits with the pinned subject, says
- [ ] mixed-dirt case: no commit, v1.1 hint text unchanged, the foreign dirty path untouched
- [ ] off-$BASE, in a worktree, or at seal time: behavior byte-identical to today (no new commit path)
- [ ] `--all` commits once with subject `docs(sprint): report refresh --all` in the only-dirt case
- [ ] the `report` drill (selftest/report.sh) asserts both the only-dirt commit and the mixed-dirt
- [ ] no new top-level function in knowledge.sh — inline the porcelain check (the api-kit surface
