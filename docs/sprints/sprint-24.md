# Sprint 24 — Away means away, small means fast (6.16.0) (2026-11-10–)

## T-289 — "POLARIS knows whether you are here: a hook records the session's mode and approval, refuses the question tool while you are away, and `polaris presence` says away or here"
points 3 · risk normal · landed 5cd2847 (2026-11-10) · claimed 2026-11-10
files touched: kit/.claude/settings.json, kit/ops/hooks/presence-guard.sh, kit/ops/install.sh, kit/ops/lib/presence.sh, kit/ops/polaris, ops/tests/perm-tools.cmd, ops/tests/presence-guard.cmd, ops/tests/presence-guard.expected, ops/tests/presence-installed.cmd, ops/tests/presence-installed.expected

### Why
The owner's rule (plans/away.md): once they approve a plan and switch the chat to auto mode, they have left, and nothing may wait on them. Today nothing even knows which of the two states a session is in, and the question tool is never intercepted, so an agent can stop on "approve this?" and sit idle for half an hour. This task is the foundation: one small hook that remembers the session's mode and whether a plan was approved, refuses the question tool while the owner is away (with a sentence telling the model what to do instead), and a `polaris presence` command that answers "away" or "here" for every later piece. Everything unknown counts as "here", so nothing changes for anyone who is still at the keyboard. Contract: ops/contracts/away.md § 0–2.

### Acceptance
- [ ] `kit/ops/hooks/presence-guard.sh` does exactly away.md § 2.2: records `<sid>.mode` on change, writes and removes `<sid>.approved` per § 1, denies `AskUserQuestion` while away with the pinned JSON and the byte-exact AWAY_SAY, prints nothing otherwise, never exits non-zero, never writes stderr; `--test` prints the four § 2.2 words
- [ ] `kit/ops/lib/presence.sh` provides the five private functions of § 2.4 and `presence` joins the literal module list in kit/ops/polaris (after `handover`)
- [ ] `bash ops/polaris presence` prints `away` or `here` and exactly one of the five pinned `   why:` lines, rc 0
- [ ] kit/ops/polaris: the `presence)` dispatch, the § 2.4 help line, and the `ui` words of § 5.1 in the `depth` help text
- [ ] kit/.claude/settings.json gains the three § 2.1 entries and nothing else changes in it; kit/ops/install.sh's `chmod +x` line names the new hook; `kit/ops/bootstrap.py` is not touched
- [ ] presence-guard golden: every case of away.md § Executable checks (B1, first bullet)
- [ ] presence-installed golden installs the kit INTO a fixture that already has a `.claude/settings.json`, shows the three entries merged, and runs the fixture's own `ops/polaris presence` for each reason
- [ ] install-update keeps its intent; its expected file changes only if the merge report really prints something new, and then only by that
- [ ] CI's Linux and macOS runs of the full self-test are green on this task's own commit (see Notes; never in verify)

## T-290 — "A closing question never ends an away run: while the owner is away the stop hook bounces it every time, with no \"ask again\" escape"
points 2 · risk normal · landed cda6b16 (2026-11-10) · claimed 2026-11-10
files touched: kit/ops/hooks/handover-hook.sh, ops/tests/stop-away.cmd, ops/tests/stop-away.expected, ops/tests/stop-question.cmd

### Why
Today the stop hook bounces a closing question once and then lets it through ("ask again and you will be let through"), so a run whose owner has left can still end on a question nobody will read for half an hour. While the owner is away (plan approved + auto mode, read from the state files the presence hook keeps), a closing question with work left must be bounced every time, with the same instruction the question tool gets. While the owner is here, nothing changes at all. Contract: ops/contracts/away.md § 3; ops/contracts/role-handover.md § v4.

### Acceptance
- [ ] away (away.md § 2.3: the Stop payload's `permission_mode`, else `<sid>.mode`, plus `<sid>.approved`) + `REPLY=q` + `next` says build|integrate|promote ⇒ `block:away` with the byte-exact reason `<AWAY_SAY> Work left - next says <l1>; do it.`
- [ ] the same holds with `stop_hook_active: true` (the `allow:harness-cap` rung is skipped for exactly that case and no other)
- [ ] away + `finish`|`tidy`|`wait`|`stop`, the `⛔` mark, or no licensing event ⇒ today's rung
- [ ] here ⇒ `ops/tests/stop-question.expected` and `ops/tests/handover-stop.expected` byte-identical
- [ ] at most ONE new function, private `_hh_away`; the state read is builtins only
- [ ] stop-away golden covers every B2 case in away.md § Executable checks; stop-question.cmd now fakes HOME and USERPROFILE (its expected file unchanged)

## T-291 — "A small UI change gets quick checks: new depth `ui` for 1-2 point component and page edits, plus the keys test_ui and qa_parallel"
points 3 · risk normal · landed 9d4dca2 (2026-11-10) · claimed 2026-11-10
files touched: kit/ops/KEYS.tsv, kit/ops/lib/core.sh, kit/ops/lib/route.sh, ops/tests/api-kit.expected, ops/tests/depth-ui.cmd, ops/tests/depth-ui.expected

### Why
The owner wants a small UI tweak to be fast: today only style and image files get the light "look" depth, so a one-line change to a component pays the whole test suite unless the runner can relate tests. This task adds the depth `ui` between `look` and `scoped`: every changed path is a UI file (test_ui) and every task in the change is 1-2 points and `risk: normal`. It also registers the key `qa_parallel` that the next task (T-295) reads. Until T-295 lands, `ui` simply runs what `scoped` runs, so nothing gets less checking in between. Contract: ops/contracts/test-depth.md § v2 (v2.1–v2.3, v2.5).

### Acceptance
- [ ] `depth_for` answers `ui` exactly per § v2.2 (rules 1–4, the two byte-exact why lines); every other input keeps today's verdict byte for byte
- [ ] kit/ops/KEYS.tsv gains the `test_ui` and `qa_parallel` rows of § v2.1 (since `6.16.0`, the pinned absent-cost lines); defaults live in code only
- [ ] `polaris depth` and `depth --commit` at `ui` print the § v2.3 lines; `depth_line_say ui` prints `depth: ui — <why>`
- [ ] depth-ui golden covers the § v2.5 list, including a fixture with the kit installed into it running its own `ops/polaris depth`
- [ ] every existing depth golden keeps its verdict; a fixture that would now qualify keeps its original intent (e.g. points 3), changed only in its .cmd, with its expected file untouched wherever possible
- [ ] keys-drift still prints `registry lacks: nothing`
- [ ] CI's Linux run of the full self-test is green on this task's own commit (see Notes; never in verify)

## T-292 — "The landing does its bookkeeping once: seal and the dones that follow under one lease refresh the brain once, after the last done"
points 2 · risk normal · landed ee87e4e (2026-11-10) · claimed 2026-11-10
files touched: kit/ops/lib/integrate.sh, kit/ops/lib/knowledge.sh, ops/tests/brain-once.cmd, ops/tests/brain-once.expected

### Why
One change costs about 60 seconds of command time on a fresh project, and 34 of them are the landing; traced on a 6.14.0 practice project, the brain (the project's generated knowledge digest) is rebuilt at the seal and again at every done that follows, inside the same lease. A self-landing handoff only needs the brain fresh once, at the end. This task makes the seal skip its refresh when dones are still to come under the same lease, and the last done refresh it. Target: a self-landing handoff in 20 s or less. Contract: ops/contracts/away.md § 7.

### Acceptance
- [ ] seal under an inherited lease, with at least one sealed task still waiting in review/ for its done, skips `brain_refresh_if_present` and touches `.polaris/brain-due`; otherwise seal is unchanged; `seal --sync` is unchanged
- [ ] done skips the refresh only under an inherited lease while another landed task still waits for its done; whichever refresh runs removes `.polaris/brain-due`
- [ ] `board_changed_touch` still runs at every site
- [ ] `brain_refresh_if_present` appends `refresh` to `$POLARIS_BRAIN_TRACE` when set; unset ⇒ byte-identical
- [ ] brain-once golden: exactly ONE refresh for a self-landing handoff that seals and dones under one lease; ONE for a plain done; no marker left after either; the fixture has the kit installed into it and runs its own `ops/polaris`
- [ ] before/after timing of a self-landing handoff on a fresh project, measured with the tracing script, is written into the handoff note (target 20 s or less; not a gate)
- [ ] CI's Linux run of the full self-test is green on this task's own commit (see Notes; never in verify)

## T-293 — "The words match: here you are asked until nothing is left, away you are never asked, and every close says how long it took and ends with the pull-request link"
points 3 · risk normal · landed 7e699f9 (2026-11-10) · claimed 2026-11-10
files touched: kit/.claude/output-styles/polaris.md, kit/CLAUDE.md, kit/ops/PROTOCOL.md, kit/ops/roles/BUILDER.md, kit/ops/roles/CONDUCTOR.md, kit/ops/roles/INTEGRATOR.md, kit/ops/roles/PLANNER.md, kit/ops/roles/SOLO.md

### Why
The rules being built in this sprint only work if every role reads the same thing: while the owner is here, ask every question that changes the plan, in rounds, until none is left; once they approve and go to auto mode, never ask, take the recommended option, park only what has no safe default, and finish through publishing. The close must also end with the pull-request link on pull-request projects, say how long the run took and where the time went, and name every high-risk task that merged on the plan's yes. kit/CLAUDE.md is paid for in every context, so it gets three lines at most. Contract: ops/contracts/away.md § 8.

### Acceptance
- [ ] kit/CLAUDE.md: Invariant 9's last sentence and the one new Away line read byte-exactly as away.md § 8; no more than THREE lines changed or added in the file; every heading byte-identical
- [ ] the five role files, PROTOCOL.md and the output style carry the § 8 rules, each where its role acts on it, and nothing else changes; every heading byte-identical (ops/tests/api-kit.expected pins them and stays green unchanged)
- [ ] PROTOCOL.md's full command table has ONE `presence` row
- [ ] PROTOCOL.md § VOICE and the output style's voice rows stay byte-identical with each other (plain-voice green)
- [ ] the output style's close rules: the pull-request link is the last line of a pull-request project's close; every close names the run's time and where it went (`bash ops/polaris speed`) and each task an `away:` line reported
- [ ] PLANNER.md: carve for side-by-side lanes; a chain longer than two tasks carries a one-line reason; the plan shown names lanes, waves and an estimated time
