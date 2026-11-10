# Sprint 23 — Nothing waits to land (6.15.0) (2026-11-09–)

## T-221 — "Race drill: prove parallel self-landing can lose a task (red before the fix)"
points 3 · risk normal · landed 510d206 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: ops/tests/land-race.cmd, ops/tests/land-race.expected

### Why
An agent elsewhere found tasks marked done whose code never reached main after about four lanes landed themselves within two minutes. Before anyone fixes the landing path we need to SEE it fail. Write a hermetic golden; the spec is ops/contracts/safe-landing.md section 8 as corrected by its v1.1 section (read v1.1 § A first: it changes how the lanes are driven). Copy self-land-finish.cmd's fixture: one throwaway repo under mktemp -d, HOME and USERPROFILE faked together, no remote, no session id, `landing: self` in CONVENTIONS, a `# SPRINT 1 — race` header (self_land refuses to land without one), test_select UNSET, and an ancestor suite stamp the way qa-stamp.cmd makes one. Put 4 tasks in ready/ (T-1..T-4, risk: normal, DISJOINT files_owned, one trivial verify line each), claim them one by one, commit one edit in each worktree, then start all four `handoff` calls at once in the background from their worktrees. That runs each lane's real self-land tail (land, then seal and done for the last lane out), which is exactly the path T-223 changes, so this .cmd never has to change again. Wait for all four, then print only facts: one line per task `<ID> <column> OK|LOST` (OK = main's file is byte-identical to the feat tip's), `waves: <n>` (integrate branches ever created, open or sealed) and `leftover-unsealed: <n>`.

### Acceptance
- [ ] the golden is hermetic (mktemp -d, trap cleanup, no live-board writes) and prints no sha, path, time or user
- [ ] .expected is the GREEN output: `T-1 done OK` .. `T-4 done OK`, `waves: 1`, `leftover-unsealed: 0`
- [ ] run against today's code it is RED (a LOST line, a task not in done, more than one wave, or one left unsealed); run it several times and record in Notes how many runs went red and which line moved
- [ ] if it can NOT be made red: do not fake it. Notes lists every interleaving tried (4 and 6 lanes, start offsets, which step was delayed) and the golden ships as a green regression guard
- [ ] the verify: lines pass (they check shape only; red-on-today is proven by your manual runs)

## T-222 — "Lease token: a lease holder's child processes inherit the lease, only the taking frame releases; a new plan's first claim re-marks the session"
points 4 · risk normal · landed 6ff502e (2026-11-09) · claimed 2026-11-09
files touched: kit/ops/lib/builder.sh, kit/ops/lib/core.sh, kit/ops/lib/workspace.sh, ops/tests/api-kit.expected, ops/tests/lease-token.cmd, ops/tests/lease-token.expected, ops/tests/plan-marker.cmd, ops/tests/plan-marker.expected

### Why
Two small fixes, both first in the chain. (1) The integration lease today only recognises the process that took it, so land, seal and done take and drop it separately and other lanes slip in between. Implement contract safe-landing section 1: int_on (workspace.sh:213) also writes `token` (holder pid + nonce) in the lease dir and exports POLARIS_INT_TOKEN; re-entry accepts a matching token as well as $$; int_off (workspace.sh:276) and on_die (core.sh:597) release ONLY in the frame that took the lease. Add the public helper int_mine (true under pid or token): land, seal and express in integrate.sh decide "did we already hold it" with their own land_had / seal_had / ex_had checks, and T-223 switches them over. Golden lease-token (hermetic): a child with the token re-enters (rc 0, no wait) and its int_off leaves the lease standing; a process without it gets the queued rc 3 path (integration_wait_minutes tiny in the fixture); the taking frame's int_off removes it. (2) Rider a of contract v1.1 (§ D): claim writes the per-session plan marker `.polaris/handover/<session>/plan` only at the FIRST claim (builder.sh:179), so a second plan run in the same session is held as foreign by `next --do`. At claim, when the marker names another plan and no task of that plan is left in active/ or review/, overwrite it with the claimed task's plan. Golden plan-marker pins the three cases of v1.1 § D. Regenerate api-kit.expected (new public name and line shifts).

### Acceptance
- [ ] lease-token golden: re-entry by token, release only by the taking frame, a tokenless process still queues
- [ ] plan-marker golden: the first claim writes the marker; a claim of plan B while plan A still has a task in active/ or review/ keeps A; once A has none there, claiming B writes B
- [ ] no output text of int_on / int_off / claim changes; self-land-finish still matches
- [ ] api-kit.expected regenerated and matches
- [ ] selftest history.sh and board.sh edited only if busyint / handover assert on what this changes

## T-226 — "Prose: tasks land themselves, the run trusts the content check, lease inheritance, and bg wait --max 120"
points 2 · risk normal · landed 075c033 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/PROTOCOL.md, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/SOLO.md, ops/contracts/shared-checkout.md, ops/contracts/worktree-liveness.md

### Why
Words only, describing the behavior in ops/contracts/safe-landing.md (T-222..T-225 build it) plus rider d of its v1.1 section (§ H). (1) INTEGRATOR.md, SOLO.md and CONDUCTOR.md: say plainly, using the phrase 'content check', that done and seal prove each task's files are on main and re-land them automatically, so no agent ever verifies main's files by hand or copies files across branches (replace any hand-verify wording in one line; no new section). (2) CONDUCTOR.md and INTEGRATOR.md: say, with the words 'lands itself at handoff', that from this release a task lands itself at handoff and an integrator is spawned only for what refused to land (risk: high, a recorded approval, a red land); `landing: integrator` stays the opt-out and its choreography stays documented. (3) PROTOCOL.md: ONE short paragraph beside the integration-lease material in § N CHATS, ONE REPO (about line 132) on lease inheritance (POLARIS_INT_TOKEN: a holder's child processes re-enter the lease, only the frame that took it releases, the lease stays outermost over the board mutex). (4) `bg wait … --max 300` becomes `--max 120` in BUILDER.md (step 5 recipe, line 60, and the "half the cap" sentence at line 64, which goes), the builder kickoff in CONDUCTOR.md (lines 198-199), SOLO.md (line 106) and PROTOCOL.md § LANES (line 137); a subagent's foreground call is moved to the background at about 180 s and `--max 120` comes back near 146 s. Leave PROTOCOL.md line 50 alone: it states the command's real default. (5) BUILDER.md, before the handoff step: in the POLARIS kit repo, a task that changed kit/ops/lib/ runs CI's one-by-one self-test on its branch ONCE before handoff, `PROOF_GOLDENS=true bash tools/proof.sh` through `bg run` + `bg wait --max 120`, and never puts it in verify. (6) shared-checkout.md and worktree-liveness.md: append a short dated note (append-only) stating the lease-token rule (naming POLARIS_INT_TOKEN) and that done now runs under the lease; earlier sections stay byte-identical. Keep every edit small: PROTOCOL.md and the role files are read often.

### Acceptance
- [ ] each file gets the described words and nothing else changes
- [ ] contracts are append-only (earlier sections byte-identical)
- [ ] verify: lines pass

## T-287 — "check --only takes a list, so a task's own checks run side by side instead of one by one"
points 2 · risk normal · landed c56c3b8 (2026-11-09) · claimed 2026-11-09 → done 2026-11-09
files touched: kit/ops/lib/check.sh, kit/ops/roles/PLANNER.md, ops/tests/check-parallel.cmd, ops/tests/check-parallel.expected

### Why
A task's own checks are now the whole gate, at handoff and again at landing. A list often names several goldens, one line each, and each line is a separate `check` run, so they go one after another: five took 8 minutes on this PC and twelve take about 12, while the same goldens run together take about 2. `--only` takes a single name pattern today, so a list has no way to ask for its goldens together. Contract: minutes.md § 15.

### Acceptance
- [ ] `check --only a,b,c` selects every golden whose name matches any of the comma-separated patterns, and runs them side by side under the existing rules when two or more are selected
- [ ] a value with no comma behaves exactly as today, byte for byte (every existing golden and drill that calls `check --only <name>` is unchanged)
- [ ] the order of the patterns never changes the output; results print in today's order
- [ ] a pattern in the list that matches nothing makes the run red and is named in the output; an empty entry is a usage error
- [ ] `--update` with a list still works one golden at a time
- [ ] golden `check-parallel` covers the four new cases of minutes.md § 15 and still covers everything it covered before
- [ ] kit/ops/roles/PLANNER.md tells the planner, where it describes verify lines, to put a task's goldens on ONE line with a list (one sentence, plain words; no heading changes)
- [ ] CI's Linux run of the full self-test is green on this task's own commit: `PROOF_GOLDENS=true bash tools/proof.sh`, once, by hand, through `bg run` (never in verify)

## T-288 — "Tasks that are only waiting no longer hold an update back, so projects stop going stale"
points 3 · risk normal · landed 11cea23 (2026-11-09) · claimed 2026-11-09
files touched: kit/.claude/skills/polaris-install/SKILL.md, kit/ops/lib/admin.sh, kit/ops/lib/selftest/fast.sh, kit/ops/lib/selftest/remote.sh

### Why
An update only applies itself when the board is "quiet", and today a task that is merely waiting in `ready/` counts as busy. The owner's four other projects each have planned tasks waiting, so `update --all` skipped every one of them (`skipped: ready: 2`, `ready: 3`) and they never update themselves at session start either: one has been on 6.7.1 since September. A waiting task is nobody's work in flight, and an update never touches the board. Only work that is being built or landed should hold an update back. Contract: ops/contracts/auto-update.md v5.

### Acceptance
- [ ] `board_quiescent` (kit/ops/lib/admin.sh) with no argument answers exactly as today; called as `board_quiescent inflight` it skips the `ready` column and judges only active/, review/, task locks, the integration lease and running bg jobs, with the same `QUIET_WHY` shapes
- [ ] `update --auto` asks `board_quiescent inflight`; the two layout-pass callers (admin.sh `update_hops_hint`, kit/ops/lib/route.sh) are unchanged and still call it with no argument
- [ ] the fan-out line reads `updating 1 other project on this PC …` for one project and `updating <n> other projects …` otherwise
- [ ] the fast tier (kit/ops/lib/selftest/fast.sh, the quiescent block) keeps every existing assertion and repeats each for `inflight`, where a task in `ready/` is quiet
- [ ] the `autoupdate` drill (kit/ops/lib/selftest/remote.sh) gains the case of auto-update.md v5 (one task in ready/, nothing else → `update --auto --say` applies and commits), keeps case (2), and checks the one-project wording
- [ ] kit/.claude/skills/polaris-install/SKILL.md's update paragraph says what is true now, as v5 describes, in plain words; no heading changes; the skill's size budget still holds
- [ ] `bash kit/ops/polaris doctor --selftest --only autoupdate` passes here, once, by hand, through `bg run` (about 12 minutes on this PC)
- [ ] CI's Linux AND macOS runs of the full self-test are green on this task's own commit: `PROOF_GOLDENS=true bash tools/proof.sh`, then `bash tools/proof.sh --await macos-latest`, each once, by hand, through `bg run` (never in verify)
