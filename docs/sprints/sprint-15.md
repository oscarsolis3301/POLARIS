# Sprint 15 — Every remaining item (6.5.0) (2026-09-14–)

## T-150 — "PROBE — does a .claude/rules file with paths: actually fire when a matching file is read? Three headless sessions in a throwaway repo, the answer recorded before any skill code exists"
points 1 · risk normal · landed fa7ce00 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: plans/self-skills.md

### Why
The owner's original ask for self-written skills, in its most literal form, was: change the
universal search bar, and what POLARIS knows about it is already in context — at zero standing
cost in every session that never touches it. Skills cannot do that (they have no `paths:`);
Claude Code's `.claude/rules/<name>.md` files with a `paths:` frontmatter are documented to load
only when a matching file is read. The T-146 spike INFERRED that from the documentation; nobody
has observed it. The owner chose "prove it first, then build": this task is the proof, and it runs
before a line of skill code exists. If the rule fires, `skill propose --write` writes a twin rule
beside every skill (contract § 6). If it does not, SK-1..SK-4 ship as plain skills and the twin is
dropped — said out loud, never shipped as a trigger nobody verified. Either answer is a success;
a guess is the only failure.

### Acceptance
- [ ] a throwaway repo built EXACTLY as `ops/contracts/self-skills.md` § "The probe" describes — two rule files, one matching file, everything committed BEFORE the first session starts
- [ ] three headless sessions run FROM INSIDE that repo (`cd <repo>; unset CLAUDECODE; claude -p …` — the contract's three prompts A/B/C verbatim), each capped at 60 s, their raw replies pasted verbatim under `## Measurements` in `plans/self-skills.md`
- [ ] the five `probe:` lines appended under `## Measurements`, exact keys from the contract, one per line, values derived ONLY from what the sessions echoed: `rules-always-fires` (A shows SK0-ALWAYS) · `rules-paths-fires-on-read` (B shows SK0-PATHS and A did not) · `rules-paths-fires-on-edit` (C; `unknown` when C could not be arranged) · `hidden-skill-absent: yes` · `nested-dir-prefix: kit:`
- [ ] one sentence under the lines saying what the answer means for SK-1: twin or no twin (contract § 0 OPEN-1)
- [ ] `polaris verify` green

## T-151 — "update --all reaches every install — the walker runs THIS kit's updater in each repo instead of the repo's own (a 5.24.0 install has no --auto to answer with), --major applies major bumps on request, gone registry entries are pruned"
points 5 · risk normal · landed bc8e58b (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/admin.sh, kit/ops/lib/selftest/remote.sh

### Why
The owner asked for every existing install to be brought current. `update --all` was built for
exactly that and cannot do it: it delegates to each registered repo's OWN `ops/polaris update --auto`,
and `--auto` only exists from 6.3.0 — so every older repo answers `⛔ update: unknown flag --auto`
and stays where it is. Measured 2026-09-14 on both of the owner's real projects (The Director 6.2.2,
pip 5.24.0). The walker is self-defeating by construction: the further behind an install is, the less
able it is to accept the update. Second-order, the same repos refuse on a dirty tree because the
app-only-dirt tolerance also landed in 6.3.0. The fix is to stop delegating: the walk runs THIS kit's
updater (the re-exec'd copy, `$SELF`, lib beside it) from inside each target checkout, so the target's
version is irrelevant — its VERSION channel, CONVENTIONS, board and locks are read as data, and the
apply step installs the target's own tarball exactly as the explicit path does. A MAJOR gap (pip →
6.5.0) still asks at session start, verbatim as before; `update --all --major` is the human's recorded
yes to apply those too. Registry entries whose path no longer exists are removed instead of printing
a failure line on every future walk (six entries on this machine after sprint 14, three of them
deleted scratch repos).

### Acceptance
- [ ] `cmd_update` parses `--major`; combines with `--all` and `--auto` only (contract v2 die texts, verbatim); `--all` accepts `--repo-only` and `--major`
- [ ] `cmd_update_all`: gone path → entry REMOVED + `<p>: gone — registry entry removed`; self-hosting line unchanged; every other entry runs `(cd "$p" && bash "$SELF" update --auto --say [--repo-only] [--major])` — the target's `ops/polaris` is never invoked; per-line prefixing unchanged; rc 0 always
- [ ] `cmd_update_auto` step 4: without `--major` the pinned MAJOR line, unchanged; with `--major` the MAJOR gap falls through to steps 5–7 and the ✅ line is v1's, unchanged
- [ ] NO new top-level fn in admin.sh (inline) — the api-kit rows for admin.sh are byte-identical
- [ ] `drill_autoupdate` (remote.sh): (6) gone line + entry ABSENT; (6b) a registered fixture whose COMMITTED `ops/polaris` is a stub that exits 1 on any invocation is updated to 0.0.2 by `--all --repo-only` and its `ops/polaris` is the real entry again; (6c) channel at 1.0.0: `--all` prints the MAJOR line under the prefix and leaves 0.0.1, `--all --major` applies; hermetic teardown unchanged
- [ ] the drill green in your worktree: `bash ops/polaris bg run t151 -- bash kit/ops/polaris doctor --selftest --only autoupdate` then chunked `bash ops/polaris bg wait t151 --max 300` until the rc is not 2 — paste the `selftest passed` line into Notes
- [ ] `bash kit/ops/polaris doctor --fast` green (the `quiescent`/`dirt` sections are unchanged)
- [ ] `polaris verify` green

## T-152 — "Stop the suite re-running for a housekeeping nit — cruft gets three classes, qa clears the provably-landed branches before drift, and a lane still standing in its own worktree is not cruft yet"
points 3 · risk normal · landed 2ce2632 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/observe.sh, kit/ops/lib/selftest/policy.sh

### Why
A self-landing lane leaves its own `feat/<ID>` behind on purpose (worktree-liveness v1.2: never
remove the ground you are standing on). `drift` then calls it CRUFT, `qa` runs `drift --strict`
AFTER the suite, goes red, writes no suite stamp — and the `finish` that follows re-runs the whole
~12-minute suite for a nit `sweep --fix` clears in a second. Observed twice on 2026-09-14; both runs
paid the suite twice for exactly this. It is structural, so the fix lives in the commands: a branch
is cruft only with PROOF that its tip landed (the squash commit's `Landed-from:` trailer, or base
ancestry); a proven branch whose worktree is still live is a lane stepping out, not cruft, and drift
says nothing; a proven idle one is cleared by `qa` before drift ever looks; an unproven one is
reported as diverged and never auto-deleted. `sweep` reuses the same function so there is one
implementation of "safe to delete".

### Acceptance
- [ ] `feat_tip_landed <ID>` and `cruft_clear` in observe.sh exactly as the contract v2 pins them (rc, notes, `wt_remove <ID> sweep` for a registered idle worktree, rc 2 archived still deletes the branch, rc 1 LEFT skips)
- [ ] `cmd_drift` check 3: waiting → SILENT · clearable → the pinned CRUFT finding · diverged → the pinned `CRUFT diverged` finding
- [ ] `cmd_qa`: `cruft_clear` immediately before `( cmd_drift --strict )`; `say "cruft — cleared <n> branch(es)"` only when n > 0
- [ ] `cmd_sweep`: clearable branches reported with the pinned ⚠ line; `--fix` calls `cruft_clear` once; the worktree pass's branch deletion now requires `feat_tip_landed`, else `⚠ feat/<ID> kept — tip not proven landed`
- [ ] `drill_drift` + `drill_qa` (policy.sh) carry the contract's fixture: clearable + diverged + waiting → drift exactly two findings; qa removes the clearable branch, keeps the diverged one, and is red for THAT reason (assert the branch list, never qa's rc alone — T-131); `sweep --fix` keeps the diverged one
- [ ] the drills green in your worktree: `bash ops/polaris bg run t152 -- bash kit/ops/polaris doctor --selftest --only drift,qa` + chunked `bg wait t152 --max 300`; paste the `selftest passed` line into Notes
- [ ] `polaris verify` green

## T-153 — "The burndown writes itself — seal appends the wave's row to ops/SPRINT.md and any lane records a lesson with polaris learned -m"
points 5 · risk normal · landed eb4b6c9 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/integrate.sh, kit/ops/lib/knowledge.sh, kit/ops/lib/selftest/history.sh

### Why
The burndown tables for sprints 12, 13 and 14 are empty and the Learned log has no bullet newer
than sprint 11, while the write-routing table still names the Integrator as the only writer — a
pen that went silent the day integration became a command (`landing: self`, `land --express`,
`next`). The owner loses the record of how work actually went, EVOLVE's "repeated Learned themes"
input is dry, and `metrics` reads "no reason recorded". The decision, owner-approved: the seal
writes the row it already has the numbers for (the wave's landed points, and what is still on the
board), and any lane records a lesson with one command instead of a hand edit of a board file.
The per-sprint report in `docs/sprints/` stays the narrative of record; SPRINT.md carries the
numbers and the lessons.

### Acceptance
- [ ] `seal_burndown_row <n> <date> <ids>` (integrate.sh) exactly as contract v3 pins it: done_pts from the wave's IDs (review/ first, done/ fallback), remaining over backlog ∪ ready ∪ active ∪ review minus the wave, the row appended as the LAST row of the TOP sprint's `## Burndown` table, the table created at the end of the top section when absent, `board_commit "chore(board): burndown <date>"` + `sync_board`, failures a ⚠ never a failed seal
- [ ] `cmd_seal` (direct) calls it right after the `--no-ff` merge; `seal_sync` (pr) after the `[<ID>]` verification; then the ONE pinned `learned anything?` nudge
- [ ] `cmd_learned` (knowledge.sh): `-m` required, ≤ 400 chars, no TAB; appends `- <YYYY-MM-DD> · <bullet>` as the last bullet of `## Learned` (created at EOF when absent); `evt learned`; `board_commit "chore(board): learned"`; `sync_board`; prints `✅ learned: <bullet>`; works from any branch and any cwd inside the repo
- [ ] `drill_express` (history.sh): after the express seal, SPRINT.md's `## Burndown` last row is `| <today> | <pts> | <remaining> |` with the fixture's numbers and the board ref's last subject is `chore(board): done <ID>` (asserts bytes + rc)
- [ ] the drill green in your worktree: `bash ops/polaris bg run t153 -- bash kit/ops/polaris doctor --selftest --only express,tcm` + chunked `bg wait t153 --max 300`; paste the `selftest passed` line into Notes
- [ ] `polaris verify` green

## T-154 — "next --do keeps its hands off foreign plans — the promote pass holds a backlog task whose plan: is not this run's under drain: plan, and says so"
points 2 · risk normal · landed dc675b2 (2026-09-14) · claimed 2026-09-14 → done 2026-09-14
files touched: kit/ops/lib/handover.sh, kit/ops/lib/selftest/board.sh

### Why
`drain: plan` exists so one "go" authorizes the plan the human approved, not the whole board. The
build scan (`next_claimable`) honours it; the promote pass (`next_promote`) does not — it promotes
any backlog task whose dependencies landed, whatever plan it belongs to. Harmless in sprint 14
(every task carried `plan: spend-less`); the first board with two plans on it silently adopts
foreign work, exactly what the knob is for. The fix mirrors the build scan's own foreign rule: know
the run's plan (the session's handover plan file, else the single slug the in-flight tasks carry),
and under `drain: plan` hold a candidate whose `plan:` is set and different — reported as a `held:`
line like the overlap hold, never a silent drop (T-130's lesson). A candidate with no `plan:` is
never foreign, so riders still flow.

### Acceptance
- [ ] `next_promote`: P per contract v2 (session plan file → single in-flight slug → none); under `drain: plan` with P known, a candidate whose `plan:` is set and ≠ P goes to `NX_HELD` with the pinned line and is NOT promoted; no `plan:` ⇒ eligible; `drain: queue|backlog` ⇒ no filtering; P unknown ⇒ byte-identical to today
- [ ] the module still has EXACTLY eight top-level fns (inline change) and stays ≤ 340 lines
- [ ] `drill_handover` (board.sh): the contract's fixture — under `drain: plan`: ready `plan: alpha`, backlog dep-satisfied `alpha` + `beta` + unplanned → `--do` promotes two, holds beta's with the pinned line, ONE board commit; under `drain: queue` all three promote; asserts `ls ready/`, the promote event count and rc
- [ ] `bash ops/tests/handover-route.cmd | diff - ops/tests/handover-route.expected` is empty (run once from your worktree root — ~47 s, so it is an acceptance check, not a verify line)
- [ ] the drill green in your worktree: `bash ops/polaris bg run t154 -- bash kit/ops/polaris doctor --selftest --only handover` + chunked `bg wait t154 --max 300`; paste the `selftest passed` line into Notes
- [ ] `polaris verify` green

## T-155 — "The skills module — lib/skills.sh (list · gaps · budget · propose · promote · demote · prune · restore) and the entry that dispatches it, plus the sprint's one-line entry fixes: qa forwards every flag, promote/amend/learned get their lines, update learns --major"
points 5 · risk normal · landed 5994d44 (2026-09-14) · claimed 2026-09-14
files touched: kit/ops/lib/skills.sh, kit/ops/polaris, ops/tests/api-kit.expected

### Why
A surface the agents rediscover every session — the api-kit golden, the role files, observe.sh —
deserves a skill: what keeps going wrong there, its public surface, the tests that cover it,
delivered whole instead of one grep line at a time. The cost side is the whole design problem: a
model-invocable skill's frontmatter rides every session's prompt in the repo. The T-146 spike found
the two facts that make it safe — a `disable-model-invocation: true` skill costs ZERO prompt bytes,
and a repo skill loads only in that repo — so every skill is born hidden and a small, budgeted shelf
is promoted by a human on evidence. This task is the module: a deterministic skeleton over the board,
the brain and the index (the same producers `pack` uses), a byte budget, an eviction rule over
`EVENTS.ndjson`, and the archive/restore pair that never deletes. It also owns the entry file this
wave, so it writes every one-line entry change the sprint needs from the contracts' pinned text:
the `qa` dispatch forwards `"$@"` (today `qa --force --full` silently drops `--full`), `promote`
becomes a runnable alias of `next --do`, `amend` and `learned` get their usage and dispatch lines
ahead of the functions T-157 and T-153 land, and `update`'s usage line shows `--major`.

### Acceptance
- [ ] `kit/ops/lib/skills.sh`: EXACTLY the 14 fns of self-skills.md § 2, ≤ 500 lines, bash 3.2 (no mapfile, no assoc arrays, no `case` inside `$(...)`), header comment only at top level; `skill_consts` sets the five constants; the writers refuse on any `feat/*` branch and commit nothing; reserved and shadowed names refused BEFORE the threshold and branch checks (the order § 5 pins)
- [ ] the twin (§ 6) written by `propose --write` and moved by `prune --apply`/`restore` IFF `plans/self-skills.md` reads `probe: rules-paths-fires-on-read: yes`; otherwise no twin anywhere and `list` prints `twin -`
- [ ] output shapes of `list` · `gaps` · `budget` · `promote` · `demote` · `prune` · `restore` · `propose` byte-exact to § 3–5 (the W3 goldens will diff them)
- [ ] entry: loader `+skills` after `handover`; usage + dispatch for `skill`, `amend`, `learned`, `promote` verbatim from self-skills § 1, grant.md v2, sprint-report.md v3, role-handover.md v2; `qa)` forwards `"$@"`; the `update` usage line reads `update [--auto|--all [--major]] [--repo-only]` and its `--all` sentence carries auto-update.md v2's addition; entry < 500 lines
- [ ] `ops/tests/api-kit.expected` = the W1 union (key-registry.md § 9): your 14 rows + T-152's two + T-153's two, in `find --api` order, 684 lines — written from the PINNED names, never from a sibling's diff
- [ ] `bash kit/ops/polaris doctor --fast` green
- [ ] `polaris verify` green
