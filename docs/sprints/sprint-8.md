# Sprint 8 — N chats, one repo (2026-08-03–)

## T-057 — "workspace.sh — id_ok, wt_add, stray-feat repair, the integration lease, wave adoption, park/unpark"
points 5 · risk normal · landed 90b6a46 (2026-08-03) · claimed 2026-08-03
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

## T-061 — "The sprint-report writer commits its own file when it is the only dirt"
points 2 · risk normal · landed 6dc7ca9 (2026-08-03) · claimed 2026-08-03
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
