# Walk away (kit 6.20.0) — plan slug `walk-away`

Phase 2 of the owner-approved program "one install, hands-free runs, lighter small changes"
(approved 2026-11-24; full program text: `C:\Users\oscar\.claude\plans\i-d-like-for-you-iterative-stearns-of-92029365-0619-40e8-8939-d1581417c574.md`).
Phase 3 (`prefs`, 6.21.0) and Phase 4 (`one-kit`, 7.0.0) are separate plans, cut after this one ships.

## The owner's words (2026-11-24)
"If you are able to make it so POLARIS handles any and all commands for us after we approve a plan
and we go into auto that way we come back to a completely finished product it would be best. The way
to do it would be if it is VERY token efficient doing so like using Haiku to run simple things like
commands for us so it saves a lot of tokens as opposed to Fable or Opus just running commands and
checking to ensure it runs it properly with no issues. When we had the agent run commands before, it
would stall and take a long time and not have hooks in case it was taking too long and we would come
back to our project after like 3 hours of being away from computer and nothing would have been
changed still." — and: "We want it to hop less if possible and run commands for us." — and: "decrease
the amount of hops to get to the location to finish projects faster (especially when it does not
need to do the full suite of tests like changing something UI/UX related)."

## Owner decisions recorded with the approval (each is the plan's yes — do not re-ask)
- Releases ship under this approval (CONVENTIONS § Release ritual). Red `finish` or red CI stops it.
- Haiku is allowed for a command-runner agent ONLY; every other part of the Haiku ban stays.
- `heal` may rewrite its own two hand-off lines in installed CLAUDE.md files (exact match only).
- The stale-tests gate stops refusing `test_skip`/`test_look` paths (one gate loosened on purpose).
- A `ui` change with no look configured still skips tests when lint or typecheck exists, and says so.
- Fonts and more image/style types join `test_look`; templates, mdx and translations stay per-repo.
- The "human only" write-routing rows are in scope for this plan: `kit/CLAUDE.md`, `kit/ops/polaris`,
  `kit/ops/hooks/*`. Kit files may be added, merged or removed under `kit/` as the design needs.
- WON'T touch: `.github/` · `ops/` by hand (only `--dogfood`) · RULES lines (none converted/removed;
  NEW lines may be added with a `#` who/why comment) · `ops/CONVENTIONS.md` values · other projects ·
  Windows security settings · no new runtime dependency.

## Measured on this machine (Windows 11, Git for Windows 2.56.1 portable, Python 3.13), 2026-11-24
`doctor` 2.2 s · `doctor --fast` 299 checks, 9 s (9.9 s wall) · `selftest-install.sh` 12 drills,
31.8 s · `doctor --selftest --parallel 3` baseline: running as bg job `baseline-selftest`.

## Section order = what it costs the owner today

### A. POLARIS runs every command; nothing waits on the owner while away
- The 🚩 hand-to-the-human rule has five homes: `kit/ops/lib/admin.sh:1467-1468` (heal_claudemd,
  appended once under HEAL_MARK, `:1457` returns early so installed repos never see a kit change),
  `kit/ops/PROTOCOL.md:267-268` (TOKEN DISCIPLINE), `kit/.claude/output-styles/polaris.md:122-139`,
  `kit/ops/roles/CONDUCTOR.md:60-73`, and the pinned text in `ops/contracts/save-hops.md`
  § Token efficiency. None has an away clause; all contradict `PROTOCOL.md:245` "finish through
  publishing". New rule (same words everywhere): long and mechanical → the agent writes the
  commands one per line and runs them detached (`bg run <name> --steps <file>`), collects once; a 🚩
  block is only for what needs a person, and only while they are here; away → the plan named it
  before approval, or it parks. `heal` migrates the old two lines by exact match, precedent
  `admin.sh:1434-1456`.
- What needs a person, exhaustively: OS elevation · sign-in/password/one-time code · a `risk: high`
  card or `ask` scope the plan did not cover, or a RULES conversion · spending money · deleting data
  that existed before the run, or a force-push · a harness denial that survives one reworded retry ·
  another machine. PLANNER lists these under "Needs you before I start"; a read-only
  `polaris preflight <slug>` checks the mechanical ones (remote reachable, `gh auth status`,
  uncovered ask/high, measured suite time). Mid-run discoveries → `polaris defer -m why -- <cmd>`.
- Raw commands that auto mode can stop on today: `git tag`/push and `python kit/ops/pack.py
  --dogfood` (`ops/CONVENTIONS.md:123,126`), `tools/proof.sh --await` (`:122`), `git switch`
  (`kit/ops/lib/qa.sh:457`), a builder's `lint:`/`typecheck:` (`BUILDER.md:54`). Route suite keys
  through the CLI (`bg run test|lint|qa`), covered by the standing `Bash(bash ops/polaris:*)` rule.
- A PermissionRequest hook that, while away and armed, denies with the away line + the park command;
  a PermissionDenied hook appends `.polaris/run/denied.tsv` for the close. (Docs: PermissionRequest
  can allow or deny on the user's behalf; auto mode pauses after 3 blocks in a row / 20 total.)

### B. The expensive model never spends a turn waiting or reading raw logs
Token arithmetic, 15-minute suite in a 150k-token context (Opus-input-equivalents; cache read
0.05x; main conversation cache 1 h, subagent cache 5 min on a subscription):
poll `bg wait --max 120` ≈ 63k · two `--max 540` waits ≈ 15k main / 375k subagent · detached job +
ONE harness wake-up ≈ 7.5k · Haiku runner ≈ 17k (the parent's own turns dominate; the runner ≈ 1k).
- Default for a top-level chat: `bg run <name> -- <cmd>`, then ONE `bg wait <name> --done` issued
  with the Bash tool's `run_in_background: true`, and end the turn; the harness wakes the session
  once; the rc file stays the truth. Fix `SOLO.md:110` ("never a background notification"), which
  contradicts `PROTOCOL.md:367-368`. `PROTOCOL.md:330` "Past that it returns NOTHING" is stale: the
  harness now moves a foreground command past its timeout to the background (docs).
- Builder subagent: collect in-turn in chunks under 5 min, or hand `running: <name>` up to its
  caller; `finish` already refuses while a job has no verdict (`qa.sh:530-542`).
- CI wait: `bg run proof-await -- bash tools/proof.sh --await macos-latest`, one backgrounded wait.
- The runner tier (owner's ask; approved): agent file `kit/.claude/agents/polaris-runner.md`
  (`tools: Bash, Read`, `model: haiku`, `maxTurns: 12`, `omitClaudeMd: true`), fixed prompt:
  run exactly `bash ops/polaris bg wait <name> --max 240` while it exits 2; reply `rc= secs=` + the
  last 15 log lines, nothing else. The CALLER starts the job (the strong model names the command).
  Used only by a top-level session when the job's measured time ≥ 300 s and `runner:` is not off.
  `route --role RUNNER` → tier cheap + `   model: <cfg model_runner haiku>` + `   agent: polaris-runner`
  (`kit/ops/lib/route.sh:287-291, 320`); new constant `model_runner_ok` (haiku|sonnet|inherit),
  fallback sonnet then the no-model path; `model_denied` (`core.sh:214-229`) unchanged.
  Guard exception in `kit/ops/hooks/model-guard.sh`: spawn door (`:270-274`) lets
  `subagent_type: polaris-runner` through; per-call (after `:387`) a Haiku session whose hook
  payload `agent_type` is `polaris-runner` may run ONLY Bash commands matching
  `^bash (\./)?ops/polaris bg (wait|status|tail) [A-Za-z0-9._-]+( (--max|-n) [0-9]+)?$`; PostToolUse
  (`:235`) same exemption. Every other Haiku session, switch, spawn and the claude-code-guide refusal
  stay byte-identical. `heal` model line (`admin.sh:1437`) gains "Haiku runs only the kit's job
  runner". New RULES content line refusing `fable|opus` on `model_runner:` (human-authored comment:
  owner 2026-11-24 via approved plan). `install.sh` copies no agents today — add the copy.
  The Planner decides, from the arithmetic above, which waiting path is each situation's default;
  the runner must never be the only path (Haiku unavailable → it falls back).

### C. A run cannot stall (all layers inert until a run is armed; unknown → today's behaviour)
Diagnosis (6.19.0): `bg` has no budget, timer or reaper (`kit/ops/lib/bg.sh`; `bg wait` answers rc 2
forever `:274-276`; only same-cwd `--force` kills, grandchildren may survive `:115-121`); `sweep`
looks only past 24 h (`observe.sh:359-371`); the Stop hook (`handover-hook.sh:181-240`) lets go on no
state, a non-completion last event, an already-used event (one block per event), ANY Agent call in
the last 200 transcript lines (nearly always true for a conductor), a ⛔ line, or `next` = wait;
nothing re-enters a stopped session (ROADMAP "Scheduled re-entry" and "`next --exec`" unchecked);
hidden foreground waits: heavy slot 1800 s (`workspace.sh:351`), lease 600 s (`:275`).
Likeliest three-hour chain: a hung job → a builder polling rc 2 forever → an idle conductor the Stop
hook lets go → a PC kept awake by the live pid.
- Arming: `presence-guard.sh` `pg_approve` (`:58-63`) also writes `<primary>/.polaris/run/<sid>.armed`
  (epoch, plan slug) when `ops/board` exists; plan mode (`:75`), `finish` rc 0 and `finish: parked`
  remove it.
- (i) Job budget in `bg_run` (`bg.sh:137-148`): the job carries its own timer; overrun kills the
  command's process tree (Git Bash: `/proc/<pid>/winpid` + `taskkill //PID //T //F`; POSIX: process
  group via `set -m`, then children, then KILL), logs why, retries once (`bg_retries` 1), then rc 124
  → `bg wait`/`status` exit 4 and print the park line. Verdicts 0-3 byte-identical
  (`bg-jobs.md:157`). `bg_budget`: 3 × the longest green run of that name (`.prev`, `.archive/`),
  else the name's class, else `.polaris/last-suite-seconds`, else 1800; floor 300 + `POLARIS_HEAVY_WAIT`
  for kit commands that can queue; `bg run --budget <s>` overrides. `bg.sh` is at its 300-line cap
  (`bg-jobs.md:83-84`): new module `kit/ops/lib/bgwatch.sh` (loader line in `kit/ops/polaris:391`).
- Busy lease / heavy slot returns `queued:` at once instead of a 10-30 minute foreground wait.
- (ii) Stall detection: `next_route` (`handover.sh:454-461`) names `   dead: <ID>` (active card, beat
  older than `wt_live_minutes`, no live job) and `   crashed: <name>` (own job, no rc, dead pid).
  New `polaris pulse` (`kit/ops/lib/pulse.sh`): line 1 `ok` | `act <next line 1>` | `done` | `parked`;
  reaps. Key `stall_minutes` 20. `pulse` only reports; only budgets kill.
- (iii) Stop gate: a new FIRST rung in `hh_stop`, builtins only. No armed file → today's ladder byte
  for byte. Armed + away + not finished/parked: Stop payload `background_tasks` non-empty → allow;
  else `next` line 1 live `wait`/`stop` → allow; else `block:run "<away line> Work left — next says
  <l1>; do it."`. Third block on the same last-event + line 1 → `allow:stalled`, a marker, and
  `notify-gate stall` (the harness also caps 8 blocks in a row). `substop` (SubagentStop): an own
  rc-less job under the subagent's cwd blocks with "collect it". `stopfail` (StopFailure) records
  the API error. Register SubagentStop + StopFailure in `kit/.claude/settings.json`. Key `away_gate` on.
- (iv) Timed re-entry: at approval the top-level role creates a session timer (CronCreate, every
  `pulse_minutes` 30, prompt: run `bash ops/polaris pulse`, follow line 1); the Stop gate reads
  `session_crons` from the payload and says "arm the pulse" when it is absent; `done`/`parked` say
  delete it. Opt-in tier 2 (`reentry: desktop`): a desktop scheduled task starting a fresh session on
  `pulse --reenter`, which inherits the approval (same plan, auto mode, within `reentry_hours` 12, at
  most `reentry_max` 3). Default `reentry: session`.
- (v) Keep-awake (`awake-hook.sh` `ah_verdict` `:191-229`): an armed unfinished run counts as active;
  an rc-less job past its budget triggers `<repo>/ops/polaris bg reap`; armed with no beat for
  `stall_minutes` writes the stalled marker and calls `notify-gate stall`. Never starts a model.
- Outcome contract (`cmd_finish`, `qa.sh:416-758`): when everything pending is human-gated, print the
  new frozen token `finish: parked - <n> waiting on you` + one `⛔ waiting on you: <command or click>
  - <reason>` line each (≤5); still exit 1 (`run-finish.md:67-71` stands); write `<sid>/parked`. On
  both endings remove the armed file and print `run: <total> - <checks> in checks, <queue> waiting,
  <n> timeouts` (from the bg registry + `.polaris/decisions.ndjson`). Output style `:141-159` and
  CONDUCTOR/SOLO step 8 carry the two shapes.

### D. Every command starts faster, no check removed
- One `wrap` = 9 full CLI starts + 3 Python starts; each start parses 1.40 MB of bash; the nine
  `selftest/*` modules are 0.52 MB and only `cmd_doctor` calls them (`observe.sh:801,825`). Load
  them only for `doctor --selftest|--fast` (`kit/ops/polaris:389-394`; module-layout lists stay
  LITERAL). `startup-budget` golden re-pinned.
- `seal` and `done` each spawn `hops --due` (Python) and `tune` (full start + `~/.claude` scan) at
  `integrate.sh:532-533` and `1527-1528`: run them once per landing, in-process. `seal_burndown_row`
  forks `fm_get` per waiting card (`integrate.sh:1017-1026`): one awk.
- `begin -` reads the draft from stdin; `wrap` commits the card's own uncommitted owned files
  (`kit/ops/lib/flow.sh`; safe: `land` squashes and takes the task's message). 6 agent calls → 4.
- `_card_reach` computed twice in `begin` (in `new`, then `pack`): compute once.

### E. Small look/text/UI changes are checked in proportion on every path
- `land --express` honours `ui` (`integrate.sh:858-944`): after `depth_line_say` set `ex_uiskip`
  and skip test/build/uat in the loop; `:944` condition gains `ex_uiskip`; shared private helper
  `_ui_skip_say` (route.sh, beside `uat_deferred_say`) also used by `qa.sh:132` (byte-identical
  line). Note: under default `landing: self`, `wrap` never calls `land --express` (`flow.sh:36-43`);
  the fix matters for `landing: integrator`, by-hand lands and the express lane.
- Stamp words: `suite_stamp_scope` (`core.sh:559`) maps everything but `scoped` to `full`, so qa and
  finish print "proven full" after none/look/ui (`qa.sh:83,649`): pass `none|look|ui|scoped` through.
  `speed` (`admin.sh:594-599`) drops ui commits: count under "would skip the test run"; `metrics`
  (`observe.sh:899-906`): print `(none a · look b · ui c · scoped d)`.
- `check_freshness` (`ownership.sh:382-469`): compose test_skip + test_look once after `:402` (set
  -f); in loop 1 after `:418` skip such paths. Guard the empty list: `owned_match` with no patterns
  reads stdin. `ui` paths stay gated.
- An edited test file (`*.test.*`, `*.spec.*`, or anything under a SURFACES `tests` glob) is never
  classed none/look/ui: it runs (narrowed when possible, never escalating a small UI change to the
  whole suite).
- `ui` floor in `depth_for` (`core.sh:79-187`): granted only when lint or typecheck is set, or both
  `visual:` and `shot:`; when no look applies the skip line adds `   ui — no before/after look is set
  up here (visual: and shot: unset): lint and typecheck are the whole check — ops/VISUAL.md`; a
  one-time offer tracked by `.polaris/look-offered`.
- `pack` prints the forecast after `builder.sh:1365` (only none/look/ui; classify owned entries
  in-process; call `depth_for` only when no entry ends in `/`): `at the finish: ui — lint and
  typecheck plus the before/after look; no test, build or uat (forecast from files_owned: the files
  you change decide)` and the look/none equivalents.
- Globs: one private helper composes the defaults (today in five places: `core.sh:94-117, 478`,
  `integrate.sh:1229`, `route.sh:412`, `admin.sh:569-571`); `test_look` += `*.avif *.bmp *.woff
  *.woff2 *.ttf *.otf *.eot *.sass *.styl *.pcss`; `+ <globs>` prefix extends a default instead of
  replacing it; KEYS.tsv rows updated.
- Stale prose: `templates/TASK.md:21-25` (test_depth takes full and ui) · `SOLO.md:116-117`,
  `PROTOCOL.md:117-118` (suite sized to the change) · `SOLO.md:22`, `kit/CLAUDE.md:22-23`,
  `PROTOCOL.md:130`, `route.sh:220` (triage does not read publish:) · `KEYS.tsv:45` (no test:
  fallback) · `kit/CLAUDE.md:96-97` (a NAMED contract exists) · `kit/ops/polaris:104-108, 202-207`,
  `PROTOCOL.md:350` (express refusals and "risk: high forces full" stale) — re-pin cli-help after
  dogfood. Specs get new `## vN` sections, never edits.

### F. Measure, then the quiet-lane tail only if it earns it
Hermetic recipe (fake HOME, throwaway repo, `test: true`/`lint: true`/`typecheck: true`, one 1-point
look card and one 1-point ui card through `begin` → `wrap`, `time` per phase; `landing: integrator`
pass to split land/seal/done/next/finish; `PS4='+ $EPOCHREALTIME '` line profile) run BEFORE and
AFTER section D. Trigger: after D, `begin` + `wrap` > 30 s (best of 3) OR > 25% of a real 1-point UI
change end to end → build the quiet-lane tail: when nothing else is in flight (landing self, express
auto, plan_covers, 1 point, depth none/look/ui, review/ holds only this card, nothing of the run in
ready/active, no open wave, primary on base, no other lock, lease free), `self_land` runs one child
`land --express <ID>` instead of three, `wrap` runs next+finish in one child, board pushes coalesce
to one under `claim: local-lock`. Worktree, lock, every handoff gate, lease, squash onto a wave,
`--no-ff` merge, tag, report, burndown, `done`'s content check, seal check and `finish` all stay.
Otherwise record the numbers and leave the tail for a later plan.

## Hard-won rules for the cards (from plans/smooth.md, still binding)
Few, large chain cards with `steps:`; disjoint files; exactly one card owns `kit/ops/polaris`
(dispatch + help + loader) and exactly one owns `ops/tests/api-kit.expected` and `kit/ops/KEYS.tsv`
per wave; `cli-help` re-pinned after the dogfood, never in a card. No seam between side-by-side cards
that only shows on the joined tree — name in the contract which goldens run the real thing and give
ONE card the job of running them on the joined tree as its last step. A card's `verify:` is its own
checks (`bash -n`, `check --only <goldens>`, `doctor --fast`), never `tools/proof.sh` or the full
suite; hook/guard changes keep their scenario matrices green. New helpers `_`-prefixed; no fixed
sleeps in goldens (budget/kill drills use tiny budgets); pipe python output through `tr -d '\r'`.
Price the plan with `bash ops/polaris speed --plan walk-away <drafts>`.

## DONE looks like
- A drill where a command hangs past its budget: killed (no grandchild left), retried once, card
  parked with the reason, run still reaches `finish`.
- A drill where an armed away session tries to stop with work left: blocked; with only human-gated
  work: `finish: parked` with one line per item; re-entry `pulse` resumes from the board.
- The runner returns the right rc and tail for a green and a red job; the guard still refuses every
  non-runner Haiku session, switch and spawn (existing model-guard matrix byte-identical).
- No 🚩 hand-off line left in the kit's own text while away; `heal` migrates an old CLAUDE.md.
- `land --express` at `ui` runs lint+typecheck only; a CSS/MD edit under a mapped surface passes
  freshness; an edited test runs; `pack` prints the forecast; "proven ui" in qa/finish.
- Timing recipe before/after D in the sprint report; the quiet-lane tail built or explicitly not.
- `bash ops/polaris finish` exits 0; release ritual complete (6.20.0 everywhere).
