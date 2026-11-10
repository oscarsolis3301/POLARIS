# Sprint 23 — Nothing waits to land (6.15.0) (2026-11-09–)

## T-221 — "Race drill: prove parallel self-landing can lose a task (red before the fix)"
points 3 · risk normal · landed 510d206 (2026-11-09) · claimed 2026-11-09
files touched: ops/tests/land-race.cmd, ops/tests/land-race.expected

### Why
An agent elsewhere found tasks marked done whose code never reached main after about four lanes landed themselves within two minutes. Before anyone fixes the landing path we need to SEE it fail. Write a hermetic golden; the spec is ops/contracts/safe-landing.md section 8 as corrected by its v1.1 section (read v1.1 § A first: it changes how the lanes are driven). Copy self-land-finish.cmd's fixture: one throwaway repo under mktemp -d, HOME and USERPROFILE faked together, no remote, no session id, `landing: self` in CONVENTIONS, a `# SPRINT 1 — race` header (self_land refuses to land without one), test_select UNSET, and an ancestor suite stamp the way qa-stamp.cmd makes one. Put 4 tasks in ready/ (T-1..T-4, risk: normal, DISJOINT files_owned, one trivial verify line each), claim them one by one, commit one edit in each worktree, then start all four `handoff` calls at once in the background from their worktrees. That runs each lane's real self-land tail (land, then seal and done for the last lane out), which is exactly the path T-223 changes, so this .cmd never has to change again. Wait for all four, then print only facts: one line per task `<ID> <column> OK|LOST` (OK = main's file is byte-identical to the feat tip's), `waves: <n>` (integrate branches ever created, open or sealed) and `leftover-unsealed: <n>`.

### Acceptance
- [ ] the golden is hermetic (mktemp -d, trap cleanup, no live-board writes) and prints no sha, path, time or user
- [ ] .expected is the GREEN output: `T-1 done OK` .. `T-4 done OK`, `waves: 1`, `leftover-unsealed: 0`
- [ ] run against today's code it is RED (a LOST line, a task not in done, more than one wave, or one left unsealed); run it several times and record in Notes how many runs went red and which line moved
- [ ] if it can NOT be made red: do not fake it. Notes lists every interleaving tried (4 and 6 lanes, start offsets, which step was delayed) and the golden ships as a green regression guard
- [ ] the verify: lines pass (they check shape only; red-on-today is proven by your manual runs)

## T-226 — "Prose: tasks land themselves, the run trusts the content check, lease inheritance, and bg wait --max 120"
points 2 · risk normal · landed 075c033 (2026-11-09) · claimed 2026-11-09
files touched: kit/ops/PROTOCOL.md, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/SOLO.md, ops/contracts/shared-checkout.md, ops/contracts/worktree-liveness.md

### Why
Words only, describing the behavior in ops/contracts/safe-landing.md (T-222..T-225 build it) plus rider d of its v1.1 section (§ H). (1) INTEGRATOR.md, SOLO.md and CONDUCTOR.md: say plainly, using the phrase 'content check', that done and seal prove each task's files are on main and re-land them automatically, so no agent ever verifies main's files by hand or copies files across branches (replace any hand-verify wording in one line; no new section). (2) CONDUCTOR.md and INTEGRATOR.md: say, with the words 'lands itself at handoff', that from this release a task lands itself at handoff and an integrator is spawned only for what refused to land (risk: high, a recorded approval, a red land); `landing: integrator` stays the opt-out and its choreography stays documented. (3) PROTOCOL.md: ONE short paragraph beside the integration-lease material in § N CHATS, ONE REPO (about line 132) on lease inheritance (POLARIS_INT_TOKEN: a holder's child processes re-enter the lease, only the frame that took it releases, the lease stays outermost over the board mutex). (4) `bg wait … --max 300` becomes `--max 120` in BUILDER.md (step 5 recipe, line 60, and the "half the cap" sentence at line 64, which goes), the builder kickoff in CONDUCTOR.md (lines 198-199), SOLO.md (line 106) and PROTOCOL.md § LANES (line 137); a subagent's foreground call is moved to the background at about 180 s and `--max 120` comes back near 146 s. Leave PROTOCOL.md line 50 alone: it states the command's real default. (5) BUILDER.md, before the handoff step: in the POLARIS kit repo, a task that changed kit/ops/lib/ runs CI's one-by-one self-test on its branch ONCE before handoff, `PROOF_GOLDENS=true bash tools/proof.sh` through `bg run` + `bg wait --max 120`, and never puts it in verify. (6) shared-checkout.md and worktree-liveness.md: append a short dated note (append-only) stating the lease-token rule (naming POLARIS_INT_TOKEN) and that done now runs under the lease; earlier sections stay byte-identical. Keep every edit small: PROTOCOL.md and the role files are read often.

### Acceptance
- [ ] each file gets the described words and nothing else changes
- [ ] contracts are append-only (earlier sections byte-identical)
- [ ] verify: lines pass

## T-287 — "check --only takes a list, so a task's own checks run side by side instead of one by one"
points 2 · risk normal · landed c56c3b8 (2026-11-09) · claimed 2026-11-09
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
