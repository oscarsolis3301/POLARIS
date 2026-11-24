# Sprint 28 — Walk away: approve, leave, come back to finished work (6.20.0) (2026-11-24–)

## T-318 — "Jobs that cannot hang - every background job has a budget and a watchdog, pulse/preflight/defer exist, next names dead cards and crashed jobs, and the CLI stops loading the self-test on every start"
points 13 · risk normal · landed 96402443 (2026-11-24) · claimed 2026-11-24
files touched: kit/ops/KEYS.tsv, kit/ops/lib/bg.sh, kit/ops/lib/bgwatch.sh, kit/ops/lib/handover.sh, kit/ops/lib/pulse.sh, kit/ops/lib/workspace.sh, kit/ops/polaris, ops/tests/api-kit.expected, ops/tests/bg-budget.cmd, ops/tests/bg-budget.expected, ops/tests/bg-lifecycle.cmd, ops/tests/bg-lifecycle.expected, ops/tests/handover-route.cmd, ops/tests/handover-route.expected, ops/tests/heavy-slot.cmd, ops/tests/heavy-slot.expected, ops/tests/lease-token.cmd, ops/tests/lease-token.expected, ops/tests/pulse-run.cmd, ops/tests/pulse-run.expected, ops/tests/startup-budget.cmd, ops/tests/startup-budget.expected

### Why
The owner came back after three hours to nothing changed: a job that hung, a builder polling `bg wait`
forever (rc 2 has no end), and a conductor the Stop hook let go. Today `bg` has no budget, no timer and
no reaper, the lease and heavy slot can hold a foreground wait for 10-30 minutes, and nothing re-enters
a stopped run. This card gives every job a budget with a watchdog that kills the whole process tree,
retries once and then answers exit 4 with a park line; adds `pulse` (what a timer-woken session runs),
`preflight` (the mechanical "needs you before I start" checks) and `defer` (park a command for the
close); makes `next` name dead cards and crashed jobs; and, armed, the lease and heavy slot never wait
in the foreground. It also owns the CLI entry script for the whole plan: the loader stops parsing the
0.52 MB self-test on every start (section D), and the help text names every new verb and flag.
`kit/ops/polaris` is in scope by the owner's word (plan walk-away, Owner decisions).

### Acceptance
- [ ] A `--budget 2` job that spawns a sleeping child is killed with no surviving process, retried once, then `bg wait` exits 4 with the pinned line (bg-budget)
- [ ] Verdicts 0-3 and every existing bg-lifecycle line byte-identical
- [ ] `pulse` prints ok/act/done/parked per § 2.2; `--reenter` counts and refuses past reentry_max (pulse-run)
- [ ] `preflight` and `defer` per § 2.3 (pulse-run)
- [ ] Unarmed, lease and heavy slot byte-identical; armed, no foreground wait (heavy-slot, lease-token)
- [ ] `next` prints dead:/crashed: lines; line 1 unchanged (handover-route)
- [ ] Non-doctor commands do not source selftest/*; startup-budget re-pinned; api-kit gains exactly the six § 0 names
- [ ] KEYS rows of § 8.2 present

## T-319 — "The away hooks - an approval arms the run, the Stop gate keeps an armed run going until it is done or parked, permission prompts park instead of waiting, and keep-awake reaps a hung job"
points 13 · risk high · landed a670a248 (2026-11-24) · claimed 2026-11-24
files touched: kit/.claude/settings.json, kit/ops/hooks/awake-hook.sh, kit/ops/hooks/handover-hook.sh, kit/ops/hooks/permission-hook.sh, kit/ops/hooks/presence-guard.sh, ops/tests/awake-hook.cmd, ops/tests/awake-hook.expected, ops/tests/handover-stop.cmd, ops/tests/handover-stop.expected, ops/tests/install-update.cmd, ops/tests/install-update.expected, ops/tests/permission-hook.cmd, ops/tests/permission-hook.expected, ops/tests/presence-guard.cmd, ops/tests/presence-guard.expected, ops/tests/presence-installed.cmd, ops/tests/presence-installed.expected, ops/tests/run-caps-plan.cmd, ops/tests/run-caps-plan.expected, ops/tests/stop-away.cmd, ops/tests/stop-away.expected, ops/tests/stop-question.cmd, ops/tests/stop-question.expected

### Why
Every stop in the three-hour failure was allowed by a hook that had no idea a run was approved and
unattended: the Stop hook lets go on any Agent call in the last 200 lines (nearly always true for a
conductor), a permission prompt sat waiting for a person who had left, and keep-awake kept the PC up
for a hung pid. This card makes the approval ARM the run (one small file), and only while armed: the
Stop gate blocks a stop that still has work, lets go when a background job or a real wait is in
flight, and after three identical blocks says "stalled" and notifies; a permission prompt is denied
with the command to park it; keep-awake counts the armed run as active and reaps a job past its
budget. Unarmed, every hook is byte-identical. Hook files are in scope by the owner's word.

### Acceptance
- [ ] Approval writes the armed file with the slug; plan mode removes it (presence-guard)
- [ ] Armed + away + work left → block:run; background task → allow:bg; next wait → allow:wait; third identical block → allow:stalled + stalled marker
- [ ] No armed file → every existing stop-away/handover-stop/stop-question/run-caps-plan line byte-identical
- [ ] permission-hook request denies only armed+away and never allows; denied appends denied.tsv only when armed
- [ ] The four new registrations merge once and a re-run is idempotent (install-update, presence-installed)
- [ ] awake-hook: armed = active, reap call, stalled marker; never starts a model

## T-320 — "A Haiku job runner the guard lets through for exactly one thing - the polaris-runner agent may run only bg wait/status/tail; every other Haiku session, switch and spawn is refused as before"
points 8 · risk high · landed 8ba214be (2026-11-24) · claimed 2026-11-24
files touched: kit/.claude/agents/polaris-runner.md, kit/ops/hooks/model-guard.sh, kit/ops/install.sh, ops/RULES.tsv, ops/tests/model-guard-v2.cmd, ops/tests/model-guard-v2.expected, ops/tests/update-arms.cmd, ops/tests/update-arms.expected

### Why
The owner asked for a cheap model to sit on long commands instead of Opus. The guard bans Haiku in
every session, spawn and switch, and that ban stays. This card cuts exactly one hole in it: a subagent
of type `polaris-runner` (a new agent file, `model: haiku`, 12 turns, no CLAUDE.md) may run only
`bash ops/polaris bg wait|status|tail <name> [--max|-n N]` and report the rc and the last 15 lines.
The strong model still starts the job and names the command, so the runner cannot do anything but
wait. If the harness does not tell hooks which agent type is calling, the hole is not built and
routing falls back — fail closed. `install.sh` learns to copy the agent file, and a RULES line keeps
anyone from pointing the runner at Fable or Opus. Hook files are in scope by the owner's word.

### Acceptance
- [ ] Existing model-guard-v2 lines byte-identical; appended: runner spawn allowed, runner `bg wait x --max 240` allowed, runner `ls` / `bg run` / `bg wait x; rm -rf .` blocked, non-runner Haiku session blocked with today's line
- [ ] polaris-runner.md frontmatter exactly per § 3.2 and no `#` heading
- [ ] install copies the agent file, idempotent, no new say line
- [ ] ops/RULES.tsv gains exactly one content line with the owner/plan comment

## T-321 — "Test depth in proportion, in the core - one glob helper with fonts and more style types, a ui floor that says when no look is set up, an edited test that always runs, honest stamp words, a freshness gate that skips docs and styles, and route --role RUNNER"
points 12 · risk normal · landed e2743e00 (2026-11-24) · claimed 2026-11-24
files touched: kit/ops/lib/core.sh, kit/ops/lib/ownership.sh, kit/ops/lib/route.sh, ops/tests/change-bound.cmd, ops/tests/change-bound.expected, ops/tests/depth-stamp.cmd, ops/tests/depth-stamp.expected, ops/tests/depth-ui.cmd, ops/tests/depth-ui.expected, ops/tests/qa-stamp.cmd, ops/tests/qa-stamp.expected, ops/tests/related-tests.cmd, ops/tests/related-tests.expected, ops/tests/route-tier.cmd, ops/tests/route-tier.expected, ops/tests/test-depth.cmd, ops/tests/test-depth.expected, ops/tests/verify-stamp.cmd, ops/tests/verify-stamp.expected

### Why
A one-line CSS or copy change should not pay for the whole suite, and today it often still does or
says the wrong thing: the default globs live in five places and miss fonts and several style types,
`ui` is granted even when there is no lint, typecheck or look to run, qa and finish print "proven
full" after a run that proved only ui, and the stale-tests gate refuses a doc or style edit under a
mapped surface. The opposite mistake also exists: an edited test file can be classed "small" and not
run. This card fixes all of it in the three core files (core.sh, route.sh, ownership.sh) so the
landing, qa and speed cards of wave 2 just call the helpers. It also adds the RUNNER routing role the
Haiku runner card (T-320) is spawned with. Owner decisions cover the loosened freshness gate and the
ui-with-no-look behaviour.

### Acceptance
- [ ] `_depth_globs` is the only place in core/route the defaults are spelled; `+ ` extends
- [ ] A CSS/MD edit under a mapped surface passes freshness; a ui path is still gated (verify-stamp)
- [ ] An edited `*.test.*` / `*.spec.*` / SURFACES tests path is never none/look/ui (change-bound, related-tests)
- [ ] ui without lint/typecheck and without visual+shot → not ui; with no look set up the line is printed once (depth-ui)
- [ ] qa/finish say "proven ui" after a ui run (qa-stamp, depth-stamp)
- [ ] `route --role RUNNER` prints cheap + model + agent lines; `runner: off` prints none (route-tier)
- [ ] No new public fn (lib-census, api-kit)

## T-322 — "Spike - measure a small change end to end before the speed-ups land, so the quiet-lane tail is built only if it earns it"
points 2 · risk normal · landed fa93547e (2026-11-24) · claimed 2026-11-24
files touched: kit/ops/bench.sh

### Why
Section F of the plan is measurement-first: before anyone builds a "quiet lane" for one-point UI
changes, we need to know how long `begin` → `wrap` really takes and where the seconds go. This card
adds the hermetic recipe to the kit's existing benchmark (`bench.sh --flow`, walk-away § 7): a fake
home and a throwaway repo, one 1-point look card and one 1-point ui card through begin → wrap, best of
3, seconds per phase, a second pass under `landing: integrator`, and an optional line profile. It runs
on this card's worktree, which is the kit BEFORE section D lands, and the numbers go in Notes. T-326
re-runs the same recipe after D and decides from it.

### Acceptance
- [ ] `bench.sh --flow` prints one phase<TAB>seconds line per phase and the `flow: begin+wrap <s>s (best of 3)` line
- [ ] `--list` prints the phase names without running anything (the verify proof)
- [ ] BEFORE numbers (both passes, best of 3) recorded in Notes with `bash ops/polaris note T-322 -m ...`
- [ ] No new public fn (api-kit) — helpers are `_flow_*`

## T-328 — "Fewer CLI starts for a small change - seal and done run the tune-up checks once, the burndown reads the board in one pass, begin reads stdin, wrap commits the card's files, the reach is computed once, and pack forecasts the check"
points 9 · risk normal · landed 3254008f (2026-11-24) · claimed 2026-11-24
files touched: kit/ops/lib/builder.sh, kit/ops/lib/flow.sh, kit/ops/lib/integrate.sh, ops/tests/flow-solo.cmd, ops/tests/flow-solo.expected, ops/tests/landed-seal.cmd, ops/tests/landed-seal.expected, ops/tests/pack-steps.cmd, ops/tests/pack-steps.expected, ops/tests/self-land-finish.cmd, ops/tests/self-land-finish.expected, ops/tests/wrap-own-folder.cmd, ops/tests/wrap-own-folder.expected

### Why
The owner asked for fewer hops to finish a small change. One `wrap` costs nine full CLI starts plus
three Python starts: `seal` and `done` each spawn `hops --due` (Python) and `tune` (a full start plus a
`~/.claude` scan), the burndown forks once per waiting card, `begin` computes the reach list twice
(in `new`, then in `pack`), `begin` needs the draft as a file on disk and `wrap` needs a separate
commit call before it. This card removes those costs in integrate.sh, flow.sh and builder.sh, so a small change takes four agent calls instead of six — and no check is removed. It
also makes `pack` tell the builder up front how the card will be checked at the finish (none, look or
ui), so a builder never runs the suite for a CSS change. It runs in wave 1 (before T-326 measures):
the forecast calls `depth_for` as it is, and picks up T-321's sharper rules once both land.

### Acceptance
- [ ] seal/done spawn no `hops --due` or `tune` child per landing beyond one in-process run; burndown is one awk (landed-seal, self-land-finish, hops-due, tune-report)
- [ ] `begin -` with the draft on stdin works and leaves no temp file (flow-solo)
- [ ] `wrap` commits the card's own uncommitted owned files and nothing else (wrap-own-folder)
- [ ] Under `begin`, `pack` prints `   reach: listed above by new` instead of recomputing `_card_reach` (flow-solo)
- [ ] `pack` prints the forecast only for none/look/ui; other pack output byte-identical (pack-*)
- [ ] No new public fn (lib-census, api-kit)

## T-329 — Kit python output is UTF-8 on Windows, so the model-guard goldens pass without PYTHONUTF8
points 2 · risk normal · landed 9731ea85 (2026-11-24) · claimed 2026-11-24
files touched: kit/ops/hooks/model-guard.sh, ops/tests/machine-armed.cmd, ops/tests/model-guard-v2.cmd

### Why
The wave seal of 2026-11-24 went red on model-guard-v2: on Windows, when neither PYTHONUTF8 nor
PYTHONIOENCODING is set, the python that model-guard.sh runs (install listing, ~line 72-74) writes the
`·` separator in the locale codepage, so the golden sees `�`. bootstrap.py already reconfigures its
streams to UTF-8; the guard's inline python does not. Make every python the guard runs print UTF-8
(e.g. `PYTHONIOENCODING=utf-8` on that call, or `sys.stdout.reconfigure(encoding="utf-8")`), and make
machine-armed's own python-printing lines do the same if they are the source there. Expected output
stays byte-identical: only the encoding changes. No decision of the guard changes.

### Acceptance
- [ ] model-guard-v2 and machine-armed green with PYTHONUTF8 and PYTHONIOENCODING unset
- [ ] every existing expected line byte-identical

## T-331 — Wave 1 seal goes green — rules-health counts the runner rule, keys-drift knows the depth-glob family
points 1 · risk normal · landed ec49afd0 (2026-11-24) · claimed 2026-11-24
files touched: ops/tests/keys-drift.cmd, ops/tests/rules-health.expected

### Why
Successor of T-330, which could not land: an in-wave fix card's branch is cut from main, and the
lines T-330 had to change in kit/ops/lib/core.sh exist only on the open wave. The 2026-11-24 wave
seal is red on two goldens left by earlier cards of this wave, and both fixes apply cleanly to main:
1. rules-health: T-320 added the approved `model_runner:` content rule (walk-away § 3.4), the 19th
   rule; ops/tests/rules-health.expected line 1 still says 18. Move it to 19.
2. keys-drift (§ 5 awk): a key read with a trailing `_` is treated as a model-tier family and needs
   `<k>strong/mid/cheap` rows. T-321's `_depth_globs` reads `cfg "test_$k"` where `$k` is one of
   skip|look|ui. Teach § 5 that the `test_` family's members are `test_skip`, `test_look`,
   `test_ui` (all three must have rows), keep the tier rule for every other family, and update the
   § 5 comment. The check stays exactly as strict: a missing member still reds it.
The expected output of keys-drift returns to `registry lacks: nothing`; no other expected line moves.
