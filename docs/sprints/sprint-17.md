# Sprint 17 — Fast (6.7.0) (2026-09-24–)

## T-173 — "model-guard v2 — the model ban reads a tiny per-session file instead of scanning the transcript, checks every spawn, and stops failing open when many agents start at once"
points 5 · risk normal · landed f221c08 (2026-09-24) · claimed 2026-09-24 → done 2026-09-24
files touched: kit/ops/bench.sh, kit/ops/bootstrap.py, kit/ops/hooks/model-guard.sh, ops/tests/machine-armed.cmd, ops/tests/machine-armed.expected, ops/tests/model-guard-v2.cmd, ops/tests/model-guard-v2.expected

### Why
The model guard runs before EVERY tool call on this machine, in every project. Today it works out
which model the session is on by scanning the last 64 KB of the conversation transcript in pure
bash, which costs 0.5–2.3 s per call. When a conductor starts several agents at once, those scans
pile up past the hook's 5-second limit, and a hook that times out lets the call through — so the
ban on Fable and Haiku is not enforced at exactly the moment it matters most. It also cannot see a
subagent's own model, so the built-in `claude-code-guide` agent (pinned to Haiku) slips past it.

This task makes the common case a single small file read. New hook branches record the model in
`~/.claude/polaris/model-state/<session_id>` when a session starts and whenever the model is
switched; every tool call then reads that one line. Only when the file is missing does the guard fall
back to the transcript, and then with one `grep` instead of a bash loop. Subagent calls read their
OWN transcript. Spawns are checked at the door: a requested Fable or Haiku model, or the
`claude-code-guide` agent type, is refused before anything starts. A switch to a forbidden model is
refused, and if a subagent still somehow ran on one, the parent is told to discard its result. The
installer registers the new events and writes `availableModels` so the harness itself excludes Fable.

Everything is specified in `ops/contracts/speed.md` § 1 and § 2 — the exact messages, the order of
checks, the state-file rule and the bench output. Haiku stays refused everywhere this sprint.

### Acceptance
- [ ] PreToolUse with a state file naming an allowed model exits 0 without reading the transcript.
- [ ] Five transcript tail shapes, including a 64 KB Workflow line whose model field sits more than 4 KB before the line's end, give the same verdict on the fallback path — pinned in `model-guard-v2`.
- [ ] `Agent` with `subagent_type` `claude-code-guide` → exit 2 with the § 2 message; `Agent`/`Task` asking for a haiku or fable model → exit 2; a `Workflow` input carrying a forbidden model → exit 2; an `Agent` with no model → exit 0.
- [ ] A subagent call (`agent_id` present) whose own transcript shows Haiku → exit 2, and the parent's transcript is not what decided it.
- [ ] `PreModelSwitch` to haiku or fable → exit 2; to opus or sonnet → exit 0. `SessionStart` and `PostModelSwitch` write the state file; a `session_id` containing `/`, `\` or `..` writes nothing.
- [ ] `PostToolUse` on `Agent` with a forbidden resolved model prints the § 2 caveat JSON and exits 0.
- [ ] Every fail-open path still exits 0: no stdin, no transcript, unreadable transcript, missing subagent transcript.
- [ ] `arm_machine` writes `availableModels` per § 2 layer 1 and the installer registers the four new events idempotently; `machine-armed` pins both on its fixture HOME.
- [ ] `bash kit/ops/bench.sh guards` prints exactly the § 1 lines, and model-guard is `ok`.
- [ ] No new api rows (speed.md § 5): new logic lives in `case` branches and inside existing functions.
- [ ] The golden touches nothing real: HOME and `POLARIS_AWAKE_HOME` point into its `mktemp -d`.

## T-174 — "ownership-guard fast path — one git call and a rules prefilter, so an ordinary edit stops paying three to five seconds"
points 3 · risk normal · landed b7c5b01 (2026-09-24) · claimed 2026-09-24 → done 2026-09-24
files touched: kit/ops/hooks/ownership-guard.sh, ops/tests/ownership-primary.cmd, ops/tests/ownership-primary.expected

### Why
Every Edit and Write in a POLARIS repo goes through `ownership-guard.sh`. It used to take about
1 s; it now takes 3.2–4.9 s, because one content rule for one file sends every write through
python, and even the fast path costs about 1.9 s since it starts three git processes and the whole
`polaris _guard` CLI. A session with 55 writes waits 80–100 s on this hook alone.

The fix does the cheap work first. One `git rev-parse` call returns everything the hook needs. The
hook then sources `ops/lib/ownership.sh` (function definitions only, no processes) and walks
`RULES.tsv` with a builtin `while read` loop, using the same `match_one` the CLI uses, so it only
calls the CLI when a rule could actually fire. Python starts only when a content rule's scope matches
the path being written, and the payload is scanned with the existing bash `jstr` and `grep -E`,
falling back to python only for `\u` escapes. Every verdict stays exactly what it is today.

Budget (enforced by T-182): a non-builder edit ≤ floor + 600 ms (`ops/contracts/speed.md` § 1).

### Acceptance
- [ ] The common path starts one git process (the three calls merged into one `rev-parse --show-toplevel --git-common-dir --abbrev-ref HEAD`).
- [ ] The RULES prefilter runs in-hook with `match_one` in a builtin loop; the CLI runs only when a rule's scope matches the path.
- [ ] Python runs only when a content rule's scope matches the path; payload text is scanned with `jstr` + `grep -E`, python only on `\u` escapes.
- [ ] `guard-denies` verdicts unchanged; `ownership-primary` gains a row proving the fast exit exists, and the pinned refusal line is unchanged.
- [ ] `drill_checkoutguard` (which drives this hook) is green unchanged.
- [ ] Non-builder Edit timed best-of-5 before and after, both numbers recorded in Notes.
- [ ] No new api rows (speed.md § 5).

## T-175 — "checkout-guard covers PowerShell — the same protection against switching the shared checkout's branch, now for this machine's primary shell"
points 2 · risk normal · landed 6507aa8 (2026-09-24) · claimed 2026-09-24 → done 2026-09-24
files touched: kit/.claude/settings.json, kit/ops/hooks/checkout-guard.sh, ops/tests/checkout-guard-denies.cmd, ops/tests/checkout-guard-denies.expected

### Why
`checkout-guard.sh` stops any session from switching the branch of the shared primary checkout,
which is the one thing that would pull the floor out from under every other session. It is wired
only to the Bash tool, but on this machine PowerShell is the primary shell, so a PowerShell
`git switch main` passes untouched. The guard's parser already understands most PowerShell forms;
it just never sees them.

Wire the guard to `Bash|PowerShell` (readonly-allow stays Bash-only), and teach the parser the few
PowerShell shapes it misses: `{` and `if (…)` / `elseif (…)` / `foreach (…)` put the next word in
command position just like `;`, and a `;` inside quotes does not split a command. While here, deny
`git restore` that rewrites the working tree in the primary, and stop denying `git branch -d`, which
never touches the checkout. `install.sh` must merge the second matcher into repos that already have
the first, without duplicating it.

### Acceptance
- [ ] `kit/.claude/settings.json` wires checkout-guard with matcher `Bash|PowerShell`; readonly-allow keeps `Bash`.
- [ ] Golden rows: `git fetch; if ($?) { git switch main }` → deny · `git restore .` → deny · `git branch -d x` → allow · `git checkout -- .` → still deny · every existing row unchanged.
- [ ] A `;` inside quotes no longer splits a command.
- [ ] `install.sh` merges the new matcher into an existing settings.json, and a second run changes nothing — shown on a `mktemp -d` fixture, output pasted in Notes.
- [ ] No new api rows (speed.md § 5).

## T-176 — "update-hook costs nothing on a normal start — a checked-today test in plain bash before the CLI starts, and no more leaked temp copies"
points 1 · risk normal · landed 5243c33 (2026-09-24) · claimed 2026-09-24 → done 2026-09-24
files touched: kit/ops/hooks/update-hook.sh, kit/ops/lib/admin.sh

### Why
At every session start, `update-hook.sh` launches the full POLARIS CLI (twice) only to discover
that it already checked for updates today. That is about 1 s here and 2–3 s in installed repos,
paid on every new chat. Worse, when `update --auto` re-runs itself from a temporary copy, it never
deletes that copy: 82 of them sit in `%TEMP%` right now, about 90 MB.

Do the cheap check first, in plain bash with no child processes: if this is the kit repo itself
(`kit/ops/pack.py` exists), stop; if `.polaris/update-cache` says `checked:` today and its
`latest:` is not newer than `version:` in `ops/VERSION`, stop. Only otherwise start the CLI, exactly
as today. The check sits BEFORE the `--test` print, so `--test` proves it. In `admin.sh`, the
re-exec removes its temporary copy when it exits.

### Acceptance
- [ ] Fresh cache (checked today, latest ≤ version) → the hook stops before starting the CLI; `--test` prints nothing.
- [ ] Self-hosting (`kit/ops/pack.py` present) → silent.
- [ ] Stale or missing cache → unchanged: `--test` still prints `would run`.
- [ ] No process starts before the cache decision: `read` builtins and `printf '%(%Y-%m-%d)T' -1` for today (the cache writes local time with `date +%Y-%m-%d`).
- [ ] `cmd_update`'s re-exec removes its temp copy on exit; count the `%TEMP%` copies before and after one `update --auto` run and record both in Notes.
- [ ] No new api rows (speed.md § 5).

## T-177 — "drift and check in seconds — one pass over the dependency graph, branch checks that loop over branches, and a check that tests the worktree it runs in"
points 3 · risk normal · landed d5b5743 (2026-09-24) · claimed 2026-09-24 → done 2026-09-24
files touched: kit/ops/lib/observe.sh, ops/tests/drift-deps.cmd, ops/tests/drift-deps.expected

### Why
`drift` is the board's hygiene audit, and it now takes about 7 minutes on this board. 94% of that
is section 7, the dependency check, which re-reads every task in every column — including 171
finished ones — once per dependency. Sprint 16 ran drift 17 times, about 30 minutes, 20 of them on
the critical path. One awk pass over all the columns returns the same verdict in under half a second.

The branch-cruft checks have the same shape: they loop over the `done/` folder and start a
`basename` process per file, when they only need to look at the few `feat/*` branches that exist.
Loop over the branches instead, and use shell builtins instead of `basename`. A `feat/*` branch
that matches no task at all is reported with one new line, so a stray branch is noticed instead of
silently slowing every `qa`.

Two more fixes to `check` ride along, because they live in this file: run from a builder's
worktree, `check` now tests THAT worktree (today it tests the primary and passes having proven
nothing), and `check --only <name>` that matches nothing now exits 1 instead of 0.

Every existing finding line stays byte-identical (`ops/contracts/speed.md` § 3).

### Acceptance
- [ ] Section 7 is one inline awk over every column (DEP MISSING + cycles); `drift-deps` pins, on a fixture with one missing dep, one cycle and one orphan `feat/*` branch, the exact § 3 lines.
- [ ] Cruft, drift's cruft section and sweep loop over `feat/*` refs, never over `done/`; no `basename` fork inside any loop in observe.sh.
- [ ] `time bash kit/ops/polaris drift` on this board: before and after recorded in Notes; after < 15 s; the verdict is unchanged.
- [ ] `check` from `.polaris/wt/<ID>` runs that worktree's `ops/tests` from that worktree's root; `--only` matching nothing → rc 1; bare `check` unchanged.
- [ ] `drill_drift` green unchanged.
- [ ] No new api rows (speed.md § 5): the awk is inline in `cmd_drift`.

## T-178 — "next in about a second — no process per background job, held tasks say why they are held, and the brain finally reads kickbacks"
points 3 · risk normal · landed 4fc90d5 (2026-09-24) · claimed 2026-09-24 → done 2026-09-24
files touched: kit/ops/lib/bg.sh, kit/ops/lib/handover.sh, kit/ops/lib/knowledge.sh, kit/ops/lib/selftest/brain.sh, ops/tests/handover-route.cmd, ops/tests/handover-route.expected

### Why
`polaris next` answers "what does this session do now?" and the compaction and Stop hooks call it
too. It takes 23–28 s, because it starts one `basename` process for each of the 153 background-job
folders in `.polaris/bg` — folders that are never cleaned up. That is past the anchor hook's 10 s
limit, so the re-anchor after compaction silently never arrives.

Replace every `basename` in those loops (handover, bg and knowledge) with shell builtins, skip the
`.prev` archive folders before doing any other work, and replace the `cat | tr` pipelines with `read`.
Let the existing age-based cleanup also remove `.prev` folders older than 7 days, keeping every
`bg-jobs.md` rule (never a live job).

Two quiet failures ride along. When `next` decides not to promote a planned task, it drops the
reason for three of the four gate failures, so planned work can vanish without a word: record a
held reason for all four (contract missing · points outside 1–5 · a dependency not done · an
ownership overlap), and print the held lines from bare `next` too. And the brain's kickback parser
can never match a kickback event, so the "what came back" lesson log has always been empty: fix the
parser and prove it with a seeded kickback in the brain drill.

### Acceptance
- [ ] Every bg-folder loop in handover.sh, bg.sh and knowledge.sh uses `${d%/}` / `${n##*/}`; `.prev` is skipped first; no `cat | tr` pipeline is left in those loops.
- [ ] Folders older than 7 days (`.prev` and `.archive/*`) are pruned inside the existing prune path; a live job is never touched; the 7 is an in-code constant, not a KEYS row.
- [ ] `next_promote` records a held reason for all four gate failures; bare `next` prints held lines; `handover-route` pins all four.
- [ ] `brain_learned` parses kickback events; `drill_brain` asserts a seeded kickback's id and note appear.
- [ ] On a quiet box with the 153 bg folders: `next` < 3 s and `next --brief` < 10 s — before and after recorded in Notes (verify allows 5 s for load).
- [ ] No new api rows (speed.md § 5).

## T-179 — "One suite per close — a green suite is kept when only leftover branches are red, and EVOLVE runs before the last qa instead of after it"
points 2 · risk normal · landed 1d8786c (2026-09-24) · claimed 2026-09-24 → done 2026-09-24
files touched: kit/ops/lib/integrate.sh, kit/ops/lib/observe.sh, kit/ops/lib/selftest/history.sh, kit/ops/lib/selftest/policy.sh, kit/ops/roles/CONDUCTOR.md, ops/tests/qa-stamp.cmd, ops/tests/qa-stamp.expected

### Why
The end of every conductor run pays for the full test suite twice, about 15 minutes each time.
The real cause is the order of the last steps: the final `qa` goes green, then EVOLVE commits its
tuning, which moves HEAD, so the next check has to run the whole suite again. On top of that, `qa`
throws away a green suite whenever the only red is leftover-branch housekeeping.

Three changes, and no gate gets weaker (`ops/contracts/speed.md` § 4):
1. CONDUCTOR step 7.5 runs EVOLVE BEFORE the final `qa`, so the last suite run certifies the tree
   that actually ships.
2. `qa` writes its suite stamp when every suite key is green and the only other reds are
   CRUFT-class (leftover branches). It still exits 1 on them, but the next `qa` at the same HEAD
   does not re-run the suite. MAP Deltas over 20 and LEARNED over 8 stay hard gates: no stamp.
3. `land --express` runs the task's `verify:` lines before `seal`, so a red one unwinds the landing
   instead of being discovered after the seal.

### Acceptance
- [ ] CRUFT-only red with a green suite → the stamp equals HEAD, rc 1, and the next `qa` runs no suite key — in `drill_qa` and in `qa-stamp`.
- [ ] A MAP Deltas > 20 red → rc 1 and NO stamp (LEARNED > 8 the same).
- [ ] `land --express` runs `verify:` before seal; a red verify unwinds and kicks back — asserted in `drill_express`.
- [ ] CONDUCTOR.md step 7.5 puts EVOLVE before the final `qa`; no heading changes; BUILDER.md and SOLO.md need no change (EVOLVE placement is conductor-only).
- [ ] `drill_finish` green; every other drill green unchanged.
- [ ] No new api rows, drill functions or drill labels (speed.md § 5): new assertions go inside the existing drills.

## T-180 — "pack and builder rider — one index call per pack, no basename loops in the builder, and a correct note about the working folder at claim"
points 1 · risk normal · landed 4d45998 (2026-09-24) · claimed 2026-09-24 → done 2026-09-24
files touched: kit/ops/index.py, kit/ops/lib/builder.sh

### Why
`pack` is the one call a builder makes to load its whole task. For every path the task owns, it
starts a fresh polaris + python + index-refresh chain to list that path's public functions — about
1–2 s per cold start for a typical task. Let `find --api` take several globs in one call (one index
build, results printed in argument order) and have `pack` call it once with the whole owned list,
keeping the per-path grouping so `pack`'s output does not change by a single byte.

Two small things ride along in `builder.sh`: its three `basename` calls inside loops become shell
builtins, and the note `claim` prints about the working folder is corrected — a subagent's Bash
resets its working folder between calls, so the note must say to use absolute paths (or `cd` in
the same call), not that a `cd` sticks.

### Acceptance
- [ ] `find --api g1 g2 …` builds the index once and prints each glob's rows in argument order; one glob behaves exactly as today.
- [ ] `cmd_pack` calls it once with the whole owned list; `pack-visual` is byte-identical.
- [ ] No `basename` left in builder.sh code.
- [ ] `claim`'s working-folder note says subagent Bash resets the folder between calls.
- [ ] `index-selfcheck` green.
- [ ] No new api rows (speed.md § 5): the loop over globs lives inside the existing functions.

## T-181 — "Laya spike — measure the System-1 encoder on this machine and answer the three harness questions Sprint 19's router depends on"
points 2 · risk normal · landed 71f9e31 (2026-09-24) · claimed 2026-09-24 → done 2026-09-24
files touched: docs/spikes/laya-s1.md

### Why
Sprint 19 plans to let Laya (github.com/oscarsolis3301/laya, a small System-1 encoder) choose
models and decide when to compact, with fixed rules still holding the veto. Before anyone builds
that, we need facts this machine can give us: how fast Laya answers as a resident process, which
host to run it on, whether it is any good at the two judgements it would make, and whether the
harness levers the plan relies on actually work. This spike writes no kit code. Its only repo
output is one verdict file, `docs/spikes/laya-s1.md`, with the headings `ops/contracts/speed.md` § 7
pins, which Sprint 19 reads instead of redoing the work.

1. Install Laya into a venv under `~/.claude/polaris/laya/`. This is a machine-level install the
   owner approved (plan D7). It is NOT a repo dependency: nothing under this repo changes except the
   verdict file, so the "adding a dependency" stop does not apply here.
2. Benchmark CPU (ONNX, already installed) as a resident process on 50 real spawn descriptions and
   prompts taken from transcripts. Only if CPU p95 > 150 ms, also benchmark the local GPU (CUDA
   torch, installed into the same venv).
3. In a throwaway repo OUTSIDE this one, probe: (a) can a PreToolUse `updatedInput` set an Agent's
   `model`? (b) does writing `autoCompactWindow` to `.claude/settings.local.json` mid-session take
   effect? (c) is a `systemMessage` from UserPromptSubmit visible to the model?
4. Measure zero-shot accuracy on 30 hand-labelled spawn difficulties and 30
   continuation-vs-new-topic prompts, each against its majority-class baseline.

### Acceptance
- [ ] The verdict file has the five § 7 headings, p50 and p95 per host measured, and a recommended host.
- [ ] Probes (a), (b) and (c) each answered `yes` / `no` / `partial` with the evidence that decided it.
- [ ] Zero-shot accuracy for both sets, each next to its majority baseline.
- [ ] Nothing in this repo changes except `docs/spikes/laya-s1.md`; the venv, the labelled sets and the throwaway probe repo live outside it.

## T-182 — "Re-pin the derived goldens — api-kit indexes the tree it runs in, and every guard is proven inside its time budget"
points 1 · risk normal · landed 3b594ff (2026-09-24) · claimed 2026-09-24
files touched: ops/tests/api-kit.cmd

### Why
Four goldens are DERIVED: they record a surface the rest of the kit produces (every function,
heading and settings key under `kit/`, the help text, the settings-drift report, the startup
budget). This sprint kept every lane surface-frozen so none of them moved mid-sprint
(`ops/contracts/speed.md` § 5). This task is the one owner at the end: it proves they still hold,
and fixes the one that could lie.

`api-kit` asks the INSTALLED CLI to index the kit, and that index is anchored to the primary
checkout, so run from a builder's worktree it silently checks the wrong tree. Make its `.cmd` index
the tree it runs in (`POLARIS_ROOT`). Then re-pin api-kit, cli-help, keys-drift and startup-budget
by comparing each golden with the live output — never by commit range — and STOP and hand back on
any hunk `speed.md` does not explain. Finally, prove every guard is inside its budget with
`bench.sh guards`, now that the three guard lanes have all landed.

### Acceptance
- [ ] `api-kit.cmd` indexes the tree it runs in, so it is not vacuous from a worktree.
- [ ] api-kit, cli-help, keys-drift and startup-budget match live output; every changed line is explained by speed.md, or the task went back.
- [ ] `bash kit/ops/bench.sh guards` exits 0: every § 1 budget met. Paste its output in Notes.
- [ ] The whole golden set is green from the primary — proven by this task's own land (`uat: bash kit/ops/polaris check`), never by a full-suite line in verify.
