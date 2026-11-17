# Sprint 25 — The hour: push once, one heavy job, fewer cards, a price on every plan (6.17.0) (2026-11-16–)

## T-300 — "One heavy job at a time on this machine: a heavy slot around every verify list, plus the three new keys"
points 3 · risk normal · landed ce36b49 (2026-11-16) · claimed 2026-11-16 → done 2026-11-16
files touched: kit/ops/KEYS.tsv, kit/ops/lib/ownership.sh, kit/ops/lib/workspace.sh, ops/tests/api-kit.expected, ops/tests/heavy-slot.cmd, ops/tests/heavy-slot.expected

### Why
On a project with a slow check (Sonoba: 14 minutes) five lanes all run their checks at once and every one of them gets slower — one card built alone takes 29 minutes, the same card beside seven others takes 119. Only the board and the landing are locked today; verify lists, `qa`, the express suite and pushes are not. This card adds a machine-wide "heavy slot" — the same atomic-folder mechanism as the landing lease, but kept under `~/.claude/polaris/heavy` so it spans every worktree and project — and wraps every verify list in it, so two heavy jobs never overlap unless the owner raises `heavy_slots`. It never refuses work: a dead holder is taken over, and after 30 minutes of waiting the job runs anyway with a note. It also files the three new keys of this release (`push`, `heavy_slots`, `target_minutes`) in the key registry, because one card must own that file. Contract: ops/contracts/hour.md § 1 and § 3.

### Acceptance
- [ ] `_heavy_on <why>` / `_heavy_off` in workspace.sh exactly as hour.md § 3 (dir, slots, token re-entry, 2-s poll, 30-s note, dead-pid / 120-min steal, POLARIS_HEAVY_WAIT fail-open, `heavy_slots: 0` = no-op); the pinned note texts byte-exact
- [ ] `run_verify_cmds` takes the slot once around the whole list and releases it after, green or red
- [ ] `int_on`, `int_off`, `int_mine` are not edited (busyint, lease-token, land-race byte-identical)
- [ ] the three KEYS.tsv rows of hour.md § 1, after `publish`, byte-exact
- [ ] new golden heavy-slot covers cases (a)–(f) of hour.md § Executable check
- [ ] no new public function (api-kit unchanged)

## T-301 — "A chain does not wait for the wave: handoff pushes nothing under push: end, the last lane out counts only this run's cards, and a waiting successor gets an early seal"
points 5 · risk normal · landed b7e9367 (2026-11-16) · claimed 2026-11-16 → done 2026-11-16
files touched: kit/ops/lib/builder.sh, kit/ops/lib/core.sh, kit/ops/lib/knowledge.sh, kit/ops/lib/selftest/history.sh, kit/ops/lib/selftest/remote.sh, ops/tests/pack-steps.cmd, ops/tests/pack-steps.expected

### Why
Three things in the landing tail make a chain of cards cost a whole wave per link. (1) Every handoff pushes `feat/<ID>` to origin — three tries, and on Sonoba each push runs the full 14-minute check — yet landing merges the LOCAL branch and `done` deletes the copy: nobody uses it. With the new `push:` key (default `end` on one computer) the handoff pushes nothing. (2) "Last lane out" seals only when ready/ and active/ are empty, so eight cards of another plan sitting in ready/ mean no lane of this run ever seals; it now counts only this run's cards (same `plan:`, or none). (3) When a card of this plan waits only on what just landed, the lane seals right away and promotes it in the same step instead of waiting for the slowest sibling. Two riders ride along because they live in these files: `pack` prints a chain card's steps, and the seal's done-card scan (`resolve_sprint_ids`) becomes one pass instead of three forks per finished card. Contract: ops/contracts/hour.md § 2 (resolver + handoff), § 6 (pack), § 7, § 8.

### Acceptance
- [ ] `_push_resolve` in core.sh beside `publish_resolve`, exactly as hour.md § 2 (unset → end on local-lock, wave on claim-branch; unknown warns once on stderr)
- [ ] handoff under `publish: direct` + `push: end` makes no push, no ⚠ Note, no push-fail event; `push: wave` and `publish: pr` byte-identical to today
- [ ] `_sl_last_out` ignores ready/active/review tasks of another non-empty plan; a card with no plan keeps today's count
- [ ] seal on demand + promote in the same step, with the pinned note; no successor → every self-land output byte-identical
- [ ] `pack` prints the pinned STEPS section only for a card with `steps:`
- [ ] `resolve_sprint_ids` within three git processes and one awk, output byte-identical
- [ ] drill_selfland gains cases (a) and (b); drill_remote and drill_pushdegrade pin their existing assertions under an explicit `push: wave` and drill_remote gains case (c) — hour.md § Executable check, T-301 row
- [ ] new golden pack-steps; `drill_report` stays green unchanged

## T-302 — "A price on every plan: speed shows build time by lanes in use and the best lane count, and speed --plan projects a plan's hours against target_minutes"
points 5 · risk normal · landed cde6903 (2026-11-16) · claimed 2026-11-16 → done 2026-11-16
files touched: kit/ops/hooks/readonly-allow.sh, kit/ops/lib/admin.sh, kit/ops/polaris, ops/tests/readonly-allow.cmd, ops/tests/readonly-allow.expected, ops/tests/speed-plan.cmd, ops/tests/speed-plan.expected, ops/tests/speed-report.cmd, ops/tests/speed-report.expected

### Why
A 66-hour plan is approved exactly like a 20-minute one, because nothing puts a time on a plan: `speed` prints two medians that no rule reads, and the conductor runs a flat five lanes whatever the log says (Sonoba: 44 minutes per card at two lanes, 97 at six). This card makes the time visible. Bare `speed` gains two lines — build time by how many lanes were in use, and the lane count that lands the most cards per hour here. `speed --plan <slug> [<draft.md>…]` counts a plan's cards, the waves on its critical path and the lanes, multiplies by this project's own medians, and compares the projection with `target_minutes:` (default 60), printing the one-time re-cut line when it is over. The planner prices its drafts before filing them; the conductor shows the projection before approval. Riders: the help lines (including the `new` line T-303 changes, since this card owns kit/ops/polaris), the dispatcher passing arguments to `speed`, and the read-only allowance for `speed --plan`. Contract: ops/contracts/hour.md § 4 and § 5.

### Acceptance
- [ ] bare `speed` prints the two lanes lines of hour.md § 4 right after `built → done`, only when a bucket has n ≥ 3
- [ ] `speed --plan <slug> [<draft.md>…]` prints exactly the lines of hour.md § 5 (and the fourth only when over target), rc 1 with the pinned line when no card carries the slug; read-only
- [ ] `cfg target_minutes 60`, non-numeric → 60
- [ ] the dispatcher passes `speed`'s arguments through; help names `speed [--plan <slug> [<draft.md>…]]` and the `new` line reads `points 1-5, or up to 13 with steps:`
- [ ] readonly-allow allows `speed --plan <slug>` with or without draft paths; `speed --apply` still asks
- [ ] new golden speed-plan; speed-report and readonly-allow re-pinned as hour.md § Executable check says

## T-303 — "Fewer, bigger cards: a chain card of up to 13 points with steps:, accepted by new, next and drift — and next reads the backlog in one pass"
points 5 · risk normal · landed d35876d (2026-11-16) · claimed 2026-11-16 → done 2026-11-16
files touched: kit/ops/lib/author.sh, kit/ops/lib/drift.sh, kit/ops/lib/handover.sh, kit/ops/lib/selftest/board.sh, kit/ops/templates/TASK.md, ops/tests/handover-route.expected, ops/tests/new-task.cmd, ops/tests/new-task.expected

### Why
Card count is the cost of a plan: every card pays a build, a landing and a wave. `new` refuses anything over 5 points and chains every draft that shares a file, so a plan can only grow more cards — Sonoba's round is 72 of them, and a one-point note waits on 32 others. The owner approved chain cards (2026-11-16): one card of up to 13 points that lists its `steps:` (each 1-5 points, own commit), carried start to finish by ONE builder. This card teaches the three gates that read points — `new`, `next`'s promote pass and `drift`'s ready gate — the same one predicate, with the pinned refusal lines, and adds the `steps:` key to the task template. Because the promote pass is the loop it rewrites anyway, it also becomes one awk pass over the backlog instead of several forks per card (about 3,100 processes over 220 cards after every board event on Sonoba). Contract: ops/contracts/hour.md § 6 and § 8.

### Acceptance
- [ ] one predicate for new / next / drift: 1-5 legal (steps optional but checked), 6-13 only with ≥2 valid steps summing to points, else refused — hour.md § 6
- [ ] the four `new` refusal lines, the `held:` line and the `READY GATE:` line byte-exact; any refusal writes nothing
- [ ] `next_promote` holds no `fm_get` and no `dep_ids`; every line `next` / `next --do` prints is byte-identical for boards without chain cards
- [ ] templates/TASK.md gains a commented `steps:` key after `points:`
- [ ] drill_newcmds gains the cases of hour.md § Executable check, T-303 row; new-task, handover-route (and fm-comments if the template change moves it) re-pinned
- [ ] route and triage untouched in code; route-tier and triage-lane stay green

## T-304 — "Code goes to origin once, at the end of a run: seal and done stop pushing under push: end, finish makes one atomic push, status says what is still on this machine"
points 5 · risk normal · landed 311d9e6 (2026-11-17) · claimed 2026-11-16 → done 2026-11-17
files touched: kit/ops/lib/integrate.sh, kit/ops/lib/observe.sh, kit/ops/lib/qa.sh, kit/ops/lib/selftest/remote.sh

### Why
The owner decided (2026-11-16): code is pushed once, at the very end of a run. Today a seal pushes the base and then the tag — two more pushes, and on a project with a pre-push check each one runs the full check — and `done` asks origin about a branch copy nobody needs. Under `push: end` (the new default on one computer; T-301 added the resolver and stopped the handoff push) a seal merges and tags on this machine only, `done` leaves origin alone, and `finish` makes ONE `git push --atomic` with the base and every sprint tag that moved: one check instead of three per wave. `push: wave` keeps today's behaviour but sends base and tag in one atomic push. `status` and `finish` say how many commits are still on this machine only. The four heavy sites in these files — the `qa` suite, the express suite and both pushes — take T-300's heavy slot, so they never overlap another heavy job. Contract: ops/contracts/hour.md § 2 and § 3 (wrapped sites).

### Acceptance
- [ ] seal / done / finish / status behave exactly as the table and lines of hour.md § 2 under `push: end` and `push: wave`; `publish: pr` byte-identical everywhere
- [ ] finish's one push: one ls-remote read, one `git push --atomic`, moved tags under `--force-with-lease`, the pinned green line, the pinned red line with rc 1 and no done signal
- [ ] `_heavy_on`/`_heavy_off` around the qa suite run, the express suite loop, finish's push and the wave-mode seal push
- [ ] drill_remote gains cases (a) and (b) of hour.md § Executable check, T-304 row, with the T-285 `git` stand-in pattern (drill_autoupdate case 10)
- [ ] keys-drift strict and green (all three key readers have landed)

## T-305 — "Release 6.17.0 - the hour: the words (Invariants 2 and 4, roles, protocol) and the version and changelog"
points 3 · risk normal · landed a358f49 (2026-11-16) · claimed 2026-11-16 → done 2026-11-17
files touched: CHANGELOG.md, kit/CLAUDE.md, kit/ops/MANUAL.md, kit/ops/PROTOCOL.md, kit/ops/VERSION, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md, kit/ops/roles/SOLO.md

### Why
6.17.0 ships the hour program (plans/hour.md): code reaches origin once, at the end of a run; one heavy job at a time per machine; chain cards of up to 13 points with steps; a chain that does not wait for the wave; a lighter board; and a price on every plan. The words have to say so, because agents follow the words: Invariant 2 still says ≤5 points, Invariant 4 still tells a builder to run the whole suite per card while BUILDER.md and SOLO.md say the opposite, and PROTOCOL says checks "cost zero" without saying they cost minutes. This card rewrites those lines (the owner's approved plan names both invariant changes), teaches the planner to price a plan with `speed --plan` and re-cut once when it runs over `target_minutes`, the conductor to take its lane count from `speed`, and the builder to build a chain card step by step — then bumps the version and writes the release notes in plain words. Contract: ops/contracts/hour.md § 9.

### Acceptance
- [ ] kit/CLAUDE.md Invariants 2 and 4 carry the pinned text of hour.md § 9, and the file grows by as few bytes as possible (it is injected into every context)
- [ ] PROTOCOL § LANES gains the two pinned sentences; the command table names `speed --plan` and the keys `push`, `heavy_slots`, `target_minutes`
- [ ] PLANNER, CONDUCTOR, BUILDER, SOLO and INTEGRATOR say what hour.md § 9 lists; MANUAL's by-hand recipe matches `push: end`
- [ ] kit/ops/VERSION reads `version: 6.17.0`; CHANGELOG.md has `## 6.17.0 — <date>` above 6.16.1, one plain bullet per change a user would notice, covering T-300 to T-304
- [ ] nothing else changes; the root ops/ copy is untouched (the dogfood is the conductor's)

## T-306 — "The tests keep their own heavy slot: check and the self-test never wait on the real one"
points 2 · risk normal · landed 26cca93 (2026-11-17) · claimed 2026-11-17
files touched: kit/ops/lib/check.sh, kit/ops/lib/selftest/remote.sh, kit/ops/lib/selftest/spine.sh

### Why
6.17.0 made every heavy check on a machine take turns through one shared slot folder. The kit's own
tests run many goldens side by side, and a golden that ran a check without faking its home reached
that real, shared slot: it waited on a sibling golden and printed a "heavy: waiting" line into its
output, so it failed beside others and passed alone. Now `check` hands every golden its own scratch
slot folder (a golden that sets its own, like heavy-slot, still wins), and the self-test does the
same for every drill, serial or sharded, so tests never touch the real slot. Outside tests nothing
changes.

### Acceptance
- [ ] the six named goldens run side by side three times with no "passed alone" note and no heavy waiting line
- [ ] heavy-slot still proves the slot itself
- [ ] doctor --fast and the CI proof stay green
