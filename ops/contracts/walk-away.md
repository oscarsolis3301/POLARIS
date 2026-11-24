# CONTRACT: walk away — approve, leave, come back to finished work   (v1 — 2026-11-24)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.
Plan: `plans/walk-away.md` (owner-approved 2026-11-24 — its "Owner decisions" are the yes for every
item below; do not re-ask them). Kit release: 6.20.0. Slug: `walk-away`.

Ten cards (T-318–T-322, T-324–T-328; T-323 was re-filed as T-328 before any claim), three waves. **Wave 1**, side by side, files disjoint: **T-318** (jobs that cannot hang:
budgets, `pulse`, `preflight`, `defer`, stall lines, the loader, every help word) · **T-319** (the away
hooks: arming, the Stop gate, the permission hooks, keep-awake — `risk: high`) · **T-320** (the Haiku
job runner and its one guard exception — `risk: high`) · **T-321** (test depth in the core: globs,
the `ui` floor, stamp words, the freshness skip, `route --role RUNNER`) · **T-322** (spike: the
small-change timing recipe, measured BEFORE section D) · **T-328** (fewer CLI starts: seal/done
once, the burndown in one awk, `begin -`, `wrap` commits, the reach once, the `pack` forecast).
**Wave 2** (after their wave-1 seams land): **T-324** (`finish: parked`, the `run:` line, notify
kinds, metrics, and `land --express` at `ui`) · **T-325** (the words + `heal` + `speed`) · **T-326**
(the quiet-lane tail — only if § 7's trigger is met; measured after section D, which is T-318's
loader + T-328, both wave 1). **Wave 3**: **T-327** (the joined tree, `api-kit`, VERSION,
CHANGELOG). (v1 re-cut once by `speed --plan`: 4 waves → 3.) The release ritual itself (tag, push, `--dogfood`, `cli-help`) is the conductor's after
`finish`, exactly as 6.19.0's was.

Plan-level decisions this contract makes (the plan delegated them to the Planner; each is an `assumed:`):
- **assumed: the default wait is the detached job + ONE backgrounded wait** (§ 3.1) — by the plan's
  own arithmetic it is the cheapest path (≈7.5k vs ≈17k for the runner). The Haiku runner is the
  second path, never the only one (§ 3.2); chunked foreground waits are the last.
- **assumed: an armed busy heavy slot never waits and never refuses** — `_heavy_on`'s rc 0 contract
  (hour.md § 3) stands; armed, it says `queued:` once and runs without the slot at once (§ 2.4).
- **assumed: `finish`, armed, switches a clean primary back to `<base>` itself** when the branch is
  already merged into `<base>` (§ 5.3) — the one raw `git switch` the plan found; everything else in
  the release ritual is named by the plan, so it is not ask material.
- **assumed: the `run:` line and every other armed-only output print only when the run is armed** —
  unarmed output stays byte-identical, so no existing golden moves for it.
- **assumed: desktop re-entry inherits the approval through the re-entry prompt's fixed prefix**
  (§ 4.4) — opt-in (`reentry: desktop`), default `session`.

## § 0 Cross-card rules (every card)
- **One owner per shared file.** `kit/ops/polaris` (dispatch + help + loader) belongs to **T-318
  alone**; its help text covers EVERY new verb and flag of this plan (§ 8.1), written from this
  contract. `ops/tests/api-kit.expected` and `kit/ops/KEYS.tsv` belong to **T-318 in wave 1**, to
  **T-325 in wave 2** (api-kit only — no wave-2 key) and to **T-327 in wave 3**. T-318 writes every
  KEYS row of this plan (§ 8.2), including the rows for keys other cards read. No card re-pins
  `cli-help`: it is re-pinned after the dogfood.
- **Public names.** New public names in this release, and no others: T-318's `cmd_pulse`,
  `cmd_preflight`, `cmd_defer` (`kit/ops/lib/pulse.sh`) and `bgwatch_budget`, `bgwatch_start`,
  `bgwatch_reap` (`kit/ops/lib/bgwatch.sh`); T-325's headings listed in § 8.3. Every other new
  function anywhere (lib, hooks, bench) is `_`-prefixed; hooks use `_hh_*`, `_pg_*`, `_ah_*`, `_ph_*`,
  `_mg_*`. `lib-census` (observe drift check route qa) gains no line. `kit/.claude/agents/polaris-runner.md`
  has no `#` heading (api-kit indexes kit `.md` headings).
- bash 3.2: no `case` inside `$(...)`, no assoc arrays, no `mapfile`, no `IFS="$(printf` (use
  `$POLARIS_TAB`); an awk `function` takes at least one parameter; never one fork per card in a loop
  over the board. Hooks stay builtins-only on their common path (one small read at most).
- **Inert until armed.** Every section-C behaviour (§ 2.4, § 4, § 5) reads the armed file (§ 1) and,
  with none, behaves byte-for-byte as 6.19.0. Unknown/unparseable state → today's behaviour.
- New CONVENTIONS keys are read with a kit-code default and never written into any project's
  CONVENTIONS. Nothing here edits `ops/CONVENTIONS.md`, `.github/`, anything under `~/.claude` (except
  the hook state dirs that already live there), or converts/removes a RULES line. No new dependency.
- Goldens are hermetic (mktemp repos, fake HOME + USERPROFILE, `POLARIS_AWAKE_HOME` and
  `POLARIS_HEAVY_DIR` inside the fixture), print no sha/time/absolute path/pid, never wait on a fixed
  `sleep` (poll an observable line; budget/kill drills use `--budget 2`-sized budgets), pipe python
  output through `tr -d '\r'`. A case about a stderr line redirects it with `2>&1` itself.
- No `tools/proof.sh`, no full-suite command and no `doctor --selftest` in any `verify:`. A drill a
  card must run by hand runs in the background (`bg run` + chunked `bg wait --max 150`) and its
  result goes in the handoff Notes.
- `kit/` is the source; root `ops/` is the dogfooded copy and no card edits it — except T-320's ONE
  new line in `ops/RULES.tsv` (§ 3.4), which is this repo's own policy file.
- A hook change keeps its scenario matrix green: existing `model-guard-v2`, `presence-guard`,
  `handover-stop`, `stop-away`, `stop-question`, `awake-hook` lines stay byte-identical; new cases are
  APPENDED (that is also how a mapped surface's tests "move", `ops/SURFACES.tsv`).
- Every refusal writes nothing and exits 1 unless stated.

## § 1 The armed run (state; T-319 writes, everyone reads)
- File: `<primary>/.polaris/run/<sid>.armed` — `<primary>` is the hook payload's `cwd` when
  `<cwd>/ops/board/` is a directory (no board there → nothing armed). Content: line 1 epoch seconds ·
  line 2 the plan slug(s) of `<sid>.approved` lines 2+, space-joined (may be empty) · line 3
  `reentries <n>` (written as `reentries 0`).
- Written by `presence-guard.sh` inside `pg_approve` (both approval paths), only when absent.
  Removed by: presence-guard when it sees mode `plan` (beside the `.approved` removal); `finish` rc 0;
  `finish: parked` (§ 5.1).
- **Armed** (kit-wide meaning) = some `<primary>/.polaris/run/*.armed` exists whose epoch is within
  `reentry_hours` (default 12) of now. `_run_armed` (T-318, `pulse.sh`, private): rc 0 armed, prints
  the newest armed file's path; rc 1 otherwise; never dies. Hooks read the file with builtins and do
  not call it.
- Siblings in `.polaris/run/` (all TAB-separated, append-only, gitignored by living under `.polaris/`):
  `deferred.tsv` (`epoch<TAB>why<TAB>command`, written by `defer`), `denied.tsv`
  (`epoch<TAB>tool<TAB>first 160 chars of the command or path`, written by the PermissionDenied hook),
  `stalled` (one line: `epoch<TAB>reason`, written by the Stop gate's third block and by keep-awake),
  `<sid>.parked` (written by `finish: parked`).

## § 2 Jobs that cannot hang (T-318: bg.sh, bgwatch.sh, pulse.sh, workspace.sh, handover.sh, polaris)
### 2.1 The job budget (`kit/ops/lib/bgwatch.sh`, new module, ≤ 300 lines)
- `bgwatch_budget <name> [<cmd…>]` prints whole seconds: `bg run --budget <s>` given → that, verbatim
  (no floor — the drills use it); else 3 × the longest GREEN duration of that name among
  `.polaris/bg/<name>.prev/` and `.polaris/bg/.archive/<name>-*/`; else the name's class — `lint`,
  `typecheck`, `build` → 900; `test`, `qa`, `selftest*`, `proof*` → 3 × `.polaris/last-suite-seconds`
  (field 1) when present; else `.polaris/last-suite-seconds` × 3; else 1800. Computed budgets get a
  floor of 300, and + `${POLARIS_HEAVY_WAIT:-1800}` when the command line contains `ops/polaris`
  (a kit command that can queue for the heavy slot).
- `bgwatch_start <dir>` launches ONE detached watchdog per job beside the runner (`bg_run`,
  `bg.sh:137-148`, gains only the call and `<dir>/budget`). The watchdog polls the job's `rc` file
  every 5 s; past the budget it kills the command's whole process tree — Git Bash:
  `/proc/<pid>/winpid` → `taskkill //PID <winpid> //T //F`; POSIX: the job runs in its own process
  group (`set -m` in the runner), `kill -TERM -<pgid>`, then the children `pkill -P`, then `KILL` after
  5 s — and appends `bg: budget <n>s passed — killed the process tree (attempt <a>)` to the job log.
- **Retry once** (`bg_retries`, default 1): the watchdog re-launches the same command in the same job
  dir (`<dir>/attempt` counts from 1), same budget. Past the retries it writes `<dir>/overrun`
  (`<budget><TAB><attempts>`) and `rc` = `124`. A command that itself exits 124 with no `overrun`
  file is an ordinary red.
- **Verdicts.** `bg wait` / `bg status` codes 0 green · 1 red · 2 running · 3 unknown stay
  byte-identical (bg-jobs.md v2). New **4** iff `<dir>/overrun` exists, one line:
  `⛔ <name> timed out — killed after <budget>s, <attempts> attempts · log: <dir>/log · park it: bash ops/polaris defer -m "<name> hung" -- <cmd>`.
- `bgwatch_reap [<name>]` (and `bg reap [<name>]`): for every rc-less job of this cwd whose age is
  past its budget (or whose watchdog pid is dead), do the watchdog's kill + overrun write itself.
  Prints one `reaped: <name>` line per job; nothing to reap → silent, rc 0.
- New `bg run` flags: `--budget <s>`; `--steps <file>` runs each non-blank, non-`#` line of `<file>`
  in order as ONE job under one budget, stopping at the first red (that line's rc is the job's rc;
  the log names the line). `bg wait <name> --done` waits with no `--max` cap (the budget bounds it) —
  the form a top-level session issues with the Bash tool's `run_in_background: true`.
- `bg.sh` stays ≤ 300 lines: everything above lives in `bgwatch.sh`; `bg.sh` changes are the calls,
  the flag parse and the exit-4 branch.

### 2.2 `polaris pulse` (`kit/ops/lib/pulse.sh`, new module, ≤ 300 lines)
- Reaps first (`bgwatch_reap`), then line 1 is exactly one of: `ok` (armed, work in flight, nothing
  for this session to do) · `act <next line 1>` (armed, `next` line 1 is not `wait`/`stop`) · `done`
  (armed and `next` line 1 is `finish` with nothing pending, or the armed file is gone after `finish`
  rc 0) · `parked` (`<sid>.parked` or `stalled` present). Not armed → `ok` plus `   not armed — the
  pulse only acts on an approved away run`. Lines 2+ are indented notes. rc 0 always. `pulse` never
  kills anything except through `bgwatch_reap` (only budgets kill).
- `pulse --reenter`: armed file within `reentry_hours` and its `reentries` < `reentry_max` (3) →
  increments line 3 and prints `reenter <slug> — run: bash ops/polaris next and follow line 1`;
  otherwise `refused: <why>` rc 1. Writes nothing else.

### 2.3 `polaris preflight <slug>` and `polaris defer` (pulse.sh)
- `preflight <slug>`: read-only. One line per mechanical check, `✅ <what>` or `⛔ needs you: <what> — <the command or click>`:
  remote reachable (`git ls-remote --heads origin` with a 20 s budget) · `gh auth status` (only when
  `publish: pr` or the plan text names `gh`) · every `risk: high` card and `ask` scope of plan
  `<slug>` that `approve --plan` does not cover · the measured suite time (`.polaris/last-suite-seconds`,
  or `unknown — the first wave gate will measure it`). Last line `preflight: clear` (rc 0) or
  `preflight: <n> need you` (rc 1).
- `defer -m "<why>" -- <cmd…>` appends `deferred.tsv` and prints `deferred: <cmd> — finish lists it`.
  No `-m` or no command → usage, rc 1, nothing written.

### 2.4 Stall lines and no foreground wait (handover.sh, workspace.sh)
- `next_route` (`handover.sh:454-461`, inline, no new fn) adds indented lines after line 1, armed or
  not: `   dead: <ID>` per active card whose beat is older than `wt_live_minutes` and that has no live
  job · `   crashed: <name>` per own job with no `rc` and a dead pid. Line 1 is unchanged.
- Armed only: the integration lease (`workspace.sh:275`) treats `wm` as 0 — the existing `queued:`
  line and rc 3 on the first busy look. The heavy slot (`_heavy_on`, `:351`): first busy look →
  `note "queued: heavy slot busy — <who> (<why>) — running without it (armed run: no foreground wait)"`,
  return 0 at once.
- `stall_minutes` (default 20) is read by `pulse` and keep-awake (§ 4.5).

### 2.5 The loader (D — `kit/ops/polaris:389-394`)
- Two LITERAL lists (module-layout v10): `doctor` → today's full list + `bgwatch pulse`; every other
  command → the same list minus the nine `selftest/*` modules. `_match|_rules|_guard` unchanged.
  `bgwatch pulse` load right after `bg`. `startup-budget` re-pinned for the shorter list.

## § 3 The runner tier (T-320 hooks/agent/install; T-321 route; T-325 words)
### 3.1 Which wait, when (the default the words teach)
| situation | path |
|---|---|
| any job measured or expected < 300 s | foreground with an explicit timeout ≥ the measured time (today) |
| top-level session, ≥ 300 s | `bg run <name> -- <cmd>` · ONE `bg wait <name> --done` with `run_in_background: true` · end the turn; the harness wakes it once; the rc file is the truth |
| top-level, ≥ 300 s, no background wake-up in this harness, `runner:` not `off` | spawn the runner (§ 3.2) with the job name |
| builder subagent | collect in-turn with `bg wait <name> --max 240` while rc 2, or hand `running: <name>` up to the caller |
| CI | `bg run proof-await -- bash tools/proof.sh --await macos-latest`, one backgrounded wait |
| runner unavailable (Haiku refused or `runner: off`) | the chunked foreground `bg wait --max 540` |

### 3.2 The agent (`kit/.claude/agents/polaris-runner.md`, T-320)
Frontmatter exactly: `name: polaris-runner` · `description:` one line · `tools: Bash, Read` ·
`model: haiku` · `maxTurns: 12` · `omitClaudeMd: true`. Body (no headings): run exactly
`bash ops/polaris bg wait <name> --max 240` while it exits 2; then reply `rc=<n> secs=<n>` and the last
15 lines of `bash ops/polaris bg tail <name> -n 15`, nothing else. It never starts a job (the caller
does). `install.sh` copies `kit/.claude/agents/*.md` into `<target>/.claude/agents/` silently (no new
say line, folded into the existing `.claude/` step) — the file is ours by path, replaced on update.

### 3.3 The guard exception (`kit/ops/hooks/model-guard.sh`, T-320, risk: high)
- Spawn door (`:270-274`): an Agent/Task call whose `subagent_type` is exactly `polaris-runner` is not
  refused for `model: haiku`. Every other spawn naming a denied model is refused byte-identically.
- Per call (after `:387`): a session whose last model is denied AND whose payload `agent_type` is
  exactly `polaris-runner` may run ONLY a Bash call whose `command` matches
  `^bash (\./)?ops/polaris bg (wait|status|tail) [A-Za-z0-9._-]+( (--max|-n) [0-9]+)?$`; any other tool
  or command → today's block line, byte-identical. PostToolUse (`:235`): a subagent whose
  `agent_type`/`subagent_type` is `polaris-runner` gets no "discard its result" caveat.
- **Build-time verification, first step:** confirm from the harness docs (the `claude-code-guide`
  agent) that hook payloads carry `agent_type` for a subagent's tool calls and `subagent_type` on the
  spawn; quote the wording in Notes. Not carried → the exception is not built, `route` falls back
  (§ 3.4), and the card says so — fail closed, never open.
- Every other Haiku session, every model switch, every spawn and the claude-code-guide refusal stay
  byte-identical: the existing `model-guard-v2` lines do not move; new cases are appended.

### 3.4 Routing (`kit/ops/lib/route.sh` + `core.sh`, T-321) and policy (T-320)
- `route --role RUNNER` → line 1 `cheap`, then the usual default lines, then
  `   model: <cfg model_runner haiku>` and `   agent: polaris-runner`. New private constant in core.sh
  `_model_runner_ok` = `haiku|sonnet|inherit`; a `model_runner` value outside it → `sonnet`;
  `runner: off` → the no-model path (no `model:` line, no `agent:` line, and the note
  `   runner off — wait with bg wait --max 540` — the caller waits per § 3.1's last row). `model_denied` itself is unchanged: Haiku
  stays denied everywhere else.
- T-320 appends to `ops/RULES.tsv` ONE `content` line on `ops/CONVENTIONS.md`:
  `^model_runner:.*([Ff]able|[Oo]pus|FABLE|OPUS)` with the comment
  `# owner 2026-11-24 via approved plan walk-away: the job runner never runs on Fable or Opus`.

## § 4 The away hooks (T-319: presence-guard, handover-hook, awake-hook, permission-hook, settings.json — risk: high)
**Build-time verification, first step:** confirm from the harness docs (`claude-code-guide`) the
payload fields this section reads — Stop `background_tasks` and `session_crons`, the SubagentStop and
StopFailure payloads, PermissionRequest's deny JSON, PermissionDenied's fields — and quote the
wording in Notes. A field the harness does not send → that branch reads as absent (today's
behaviour), never as "allow everything".
### 4.1 Arming — § 1 (presence-guard `pg_approve` + the plan-mode removal; builtins only).
### 4.2 The Stop gate — a new FIRST rung in `hh_stop`, builtins only
- No armed file for this `<primary>` → the existing ladder, byte for byte.
- Armed + away (`_hh_away`) + no `finished`/`<sid>.parked`: payload `background_tasks` non-empty →
  `allow:bg`; else `next` line 1 (`POLARIS_HANDOVER_NEXT` honoured) is `wait`/`stop` → `allow:wait`;
  else `block:run` with reason `<the away line> Work left — next says <l1>; do it.` (the away line =
  `PG_SAY`'s words). Payload `session_crons` holding no cron whose prompt contains `ops/polaris pulse` →
  the reason gains ` Arm the pulse: CronCreate every <pulse_minutes> min, prompt "bash ops/polaris pulse, then follow line 1".`
- The THIRD block on the same last-event + line 1 → `allow:stalled`, writes `stalled`, and runs
  `bash <primary>/ops/polaris notify-gate stall` in the background (`&`, output discarded). The
  counter lives in `<primary>/.polaris/handover/<sid>/run-blocks` (`<event><TAB><l1><TAB><n>`).
- `away_gate: off` → the rung is skipped (key default `on`).
- `substop` (SubagentStop): an own rc-less job whose dir's `cwd` file is under the subagent's cwd →
  `block:collect` `Your job <name> is still running: bash ops/polaris bg wait <name> --max 240 (repeat while rc 2).`;
  else silent. `stopfail` (StopFailure): append `<epoch><TAB><error type>` to
  `<primary>/.polaris/run/stopfail.tsv`; never blocks.
- `--test` words: `allow:bg` · `allow:wait` · `block:run` · `allow:stalled` · `substop:collect` ·
  `substop:none` · `stopfail:recorded`.

### 4.3 The permission hooks (`kit/ops/hooks/permission-hook.sh`, new, ≤ 200 lines, builtins only)
- `permission-hook.sh request` (PermissionRequest): armed + away → deny with
  `<away line> This needs a person: park it — bash ops/polaris defer -m "<tool> needed approval" -- <command>`
  (JSON shape per the harness docs, verified at build time and quoted in Notes); otherwise no output.
  Never allows on the user's behalf.
- `permission-hook.sh denied` (PermissionDenied): armed → append `denied.tsv`; never prints.
- Registration in `kit/.claude/settings.json`: `PermissionRequest`, `PermissionDenied`,
  `SubagentStop` (handover-hook `substop`), `StopFailure` (handover-hook `stopfail`); timeouts ≤ 10 s.
  The existing entries stay byte-identical (install.sh merges per event by script path).
- `--test` words: `deny:away` · `allow:here` · `denied:recorded` · `denied:not-armed`.

### 4.4 Desktop re-entry (opt-in, `reentry: desktop`)
presence-guard, on UserPromptSubmit whose prompt starts with `POLARIS re-entry:` and an armed file
within `reentry_hours` whose `reentries` < `reentry_max`: writes `<sid>.approved` (line 1 now, line 2
the armed file's slug). Nothing else. `reentry: session` (default) → the prefix means nothing.

### 4.5 Keep-awake (`awake-hook.sh` `ah_verdict`, `:191-229`)
Armed and unfinished counts as `active`. An rc-less job past its budget → runs
`<repo>/ops/polaris bg reap` (background, output discarded). Armed with no beat for `stall_minutes`
→ writes `stalled` and `notify-gate stall` (once per stall). It never starts a model.

## § 5 The outcome (T-324: qa.sh, observe.sh — plus § 6's express `ui` in integrate.sh)
### 5.1 `finish: parked`
When everything pending is human-gated (deferred items, denied items, a `risk: high` card or `ask`
scope the plan did not cover, a `stalled` marker): print the frozen token
`finish: parked - <n> waiting on you` then one `⛔ waiting on you: <command or click> - <reason>` line
each (≤ 5; more → `   … and <m> more — .polaris/run/`), exit 1 (run-finish.md v3 rc stands), write
`<sid>.parked` (sid from `CLAUDE_SESSION_ID` when set, else `unknown`), remove the armed file.
Any non-human-gated pending item → today's output.
### 5.2 The `run:` line (armed runs only)
On rc 0 and on `finish: parked`, last line: `run: <total> - <checks> in checks, <queue> waiting, <n> timeouts`
(durations via the existing `bg_age` words; from the bg registry, `.prev`/`.archive` of this run since
the armed epoch, and `.polaris/decisions.ndjson` when present). rc 0 also removes the armed file.
### 5.3 Off base, armed
`finish` on a non-base branch, armed, clean tree, branch already merged into `<base>` → runs
`git switch <base>` itself with `note "switched back to <base> (armed run)"` and continues; any other
case → today's `fin_pending` line.
### 5.4 Words in qa, notify kinds, metrics
- `qa.sh:132` prints through `_ui_skip_say` (T-321) — byte-identical text.
- `notify-gate stall` (EV=waiting NOTE=run-stalled SEVERITY=gate) and `notify-gate parked`
  (EV=waiting NOTE=run-parked SEVERITY=gate); the usage line names both.
- `metrics` (`observe.sh:899-906`): the skipped-suite line gains `(none a · look b · ui c · scoped d)`.

## § 6 Test depth in proportion (T-321 core.sh/route.sh/ownership.sh; T-328; T-325)
- **One glob helper** `_depth_globs <skip|look|ui>` (core.sh, private) composes the defaults once; the
  five places (`core.sh:94-117, 478`, `integrate.sh:1229`, `route.sh:412`, `admin.sh:569-571`) call it
  (core/route by T-321, integrate by T-324, admin by T-325). `test_look` default +=
  `*.avif *.bmp *.woff *.woff2 *.ttf *.otf *.eot *.sass *.styl *.pcss`. A configured value starting
  with `+ ` extends the default instead of replacing it (`test_skip`, `test_look`, `test_ui`).
- **An edited test file is never small**: a path matching `*.test.*`, `*.spec.*`, or a SURFACES
  `tests` glob is never classed none/look/ui by `depth_for`; it is `scoped` when `test_select:` can
  narrow it, never escalating to `full` on its own.
- **The `ui` floor** (`depth_for`, `core.sh:79-187`): granted only when `lint:` or `typecheck:` is
  set, or both `visual:` and `shot:` are. Granted with no look configured, the skip line adds
  `   ui — no before/after look is set up here (visual: and shot: unset): lint and typecheck are the whole check — ops/VISUAL.md`
  once per repo (`.polaris/look-offered`).
- `_ui_skip_say` (route.sh, beside `uat_deferred_say`): prints exactly today's `qa.sh:132` note.
- `suite_stamp_scope` passes `none|look|ui|scoped` through; anything else / 2-field stamp → `full`.
  qa and finish therefore print `proven ui` etc. The carry path (`qa.sh:174`) keeps the word it reads.
- **Freshness** (`check_freshness`, `ownership.sh:382-469`): composes `test_skip` + `test_look` once
  after `:402` (under `set -f`); loop 1 skips such paths after `:418`. An empty list never reaches
  `owned_match` (it reads stdin with no patterns). `ui` paths stay gated.
- **`land --express` honours `ui`** (`integrate.sh:858-944`, T-324): after `depth_line_say` set
  `ex_uiskip`, call `_ui_skip_say`, skip test/build/uat in the loop; the `:944` condition gains
  `ex_uiskip`.
- **`pack` forecast** (`builder.sh` after `:1365`, T-328 — wave 1, so it calls today's `depth_for`
  in-process and inherits T-321's rules when both land): only for none/look/ui, classifying owned
  entries in-process (call `depth_for` only when no entry ends in `/`):
  `at the finish: ui — lint and typecheck plus the before/after look; no test, build or uat (forecast from files_owned: the files you change decide)`;
  `at the finish: look — the before/after look; no test run (forecast from files_owned: …)`;
  `at the finish: none — no test run (forecast from files_owned: …)`.
- `speed` (`admin.sh:594-599`, T-325): ui commits count under "would skip the test run".

## § 7 Fewer starts, and the quiet-lane tail (D: T-318 loader, T-328; F: T-322, T-326)
- T-328: `seal` and `done` run `hops --due` and `tune` once per landing, in-process
  (`integrate.sh:532-533`, `1527-1528`); `seal_burndown_row` reads every waiting card's fields in ONE
  awk (`:1017-1026`). `begin -` reads the draft from stdin (into a temp file under `.polaris/`, removed
  after). `wrap` first commits the card's own uncommitted owned files (`feat(<scope>): wip <ID>` on its
  branch — `land` squashes and takes the task's message). `begin` computes `_card_reach` once:
  `begin` exports `POLARIS_BEGIN=1` to its `pack` child, and that `pack` prints
  `   reach: listed above by new` in place of the section (new printed the same list right above it);
  `author.sh` is not touched (owning it would auto-add the `new-task.*` glob — see T-328's Notes).
- **Recipe (T-322, `kit/ops/bench.sh --flow`, private `_flow_*` fns):** fake HOME/USERPROFILE,
  throwaway repo with `test: true`, `lint: true`, `typecheck: true`; one 1-point look card and one
  1-point ui card through `begin` → `wrap`; best of 3, wall seconds per phase (`new`, `triage`,
  `claim`, `pack`, `handoff`, `land`, `next`, `finish`); a second pass under `landing: integrator`
  splits land/seal/done/next/finish; `--profile` adds a `PS4='+ $EPOCHREALTIME '` line profile of the
  slowest phase (top 15 lines). Output one `phase<TAB>seconds` line each, then
  `flow: begin+wrap <s>s (best of 3)`. Run with no heavy job on the machine (`bg status`).
- **Trigger (T-326 checks first):** after D, `begin`+`wrap` > 30 s best of 3, OR > 25% of a real
  1-point UI change end to end (when none was timed this run: `metrics`' 1pt p50). Met → build the
  tail; not met → record both numbers in the card and `release --to backlog -m "trigger not met: <numbers>"`.
- **The tail (only if met):** when nothing else is in flight (landing self, express auto,
  plan_covers, 1 point, depth none/look/ui, review/ holds only this card, nothing of the run in
  ready/active, no open wave, primary on base, no other lock, lease free), `self_land` runs one child
  `land --express <ID>` instead of three; `wrap` runs next+finish in one child; board pushes coalesce
  to one under `claim: local-lock`. Worktree, lock, every handoff gate, lease, squash onto a wave,
  `--no-ff` merge, tag, report, burndown, `done`'s content check, seal check and `finish` all stay.

## § 8 Words (T-318 help; T-325 prose + heal; T-327 release)
### 8.1 Help (`kit/ops/polaris`, T-318)
Dispatch `pulse) shift; cmd_pulse "$@";;`, `preflight)`, `defer)`. Help entries: `pulse [--reenter]`
· `preflight <slug>` · `defer -m "why" -- <cmd…>` · `bg run <name> [--force] [--budget <s>] [--steps <file>] [-- <cmd…>]`
· `bg wait <name> [--max <s> | --done]` (exit 4 = timed out) · `bg reap [<name>]` · `begin <draft.md | ->`
· `notify-gate` gains `stall | parked`. The stale lines `kit/ops/polaris:104-108, 202-207` (express
refusals; "risk: high forces full") are rewritten to today's behaviour.
### 8.2 KEYS rows (T-318, since 6.20.0)
`bg_retries` 1 · `stall_minutes` 20 · `away_gate` on · `pulse_minutes` 30 · `reentry` session ·
`reentry_hours` 12 · `reentry_max` 3 · `runner` on · `model_runner` haiku; `test_look` default
extended (§ 6) and its absent-cost words name the fonts; `test_skip`/`test_look`/`test_ui` rows say
`+ <globs>` extends; `KEYS.tsv:45` stale words fixed. Absent-cost words follow the file's style.
### 8.3 Prose (T-325)
- **The 🚩 rule, same words in all five homes** (`admin.sh` heal block, `PROTOCOL.md:267-268`,
  `output-styles/polaris.md:122-139`, `CONDUCTOR.md:60-73`, and this contract's § 9 pin):
  `- **Long, mechanical, no judgement in it?** Run it yourself, detached: one command per line in a file, then`
  `  `bash ops/polaris bg run <name> --steps <file>` and collect once. 🚩 only what needs a person, only while they are here.`
  `heal` replaces the OLD two lines (save-hops § Token efficiency) by exact whole-line match, first hit
  only, line endings kept — the `admin.sh:1434-1456` precedent. The heal model line `mn` becomes
  `- **Size every helper** — pass the model and effort `route` prints on each spawn; Haiku runs only the kit's job runner, and Fable runs only when the owner picks it.`
  and the old `mn` joins the migrated list.
- **What needs a person, exhaustively** (PLANNER.md heading `## Needs you before I start`, the one new
  role heading; CONDUCTOR/SOLO point to it): OS elevation · sign-in/password/one-time code · a
  `risk: high` card or `ask` scope the plan did not cover, or a RULES conversion · spending money ·
  deleting data that existed before the run, or a force-push · a harness denial that survives one
  reworded retry · another machine. Mechanical ones: `bash ops/polaris preflight <slug>`. Mid-run:
  `defer`.
- `output-styles/polaris.md`: the heading `🚩 Handing a step to the human` stays; its body and the
  endings section (`:141-159`) carry `finish: parked` and the `run:` line. CONDUCTOR/SOLO step 8
  carry both endings; CONDUCTOR arms the pulse at approval (CronCreate, `pulse_minutes`) and deletes
  it at `done`/`parked`.
- Waits: § 3.1's table goes in PROTOCOL § LONG COMMANDS; `SOLO.md:110` ("never a background
  notification") and `PROTOCOL.md:330` ("returns NOTHING") are corrected; `BUILDER.md:54` runs
  `lint:`/`typecheck:` through `bg run lint|typecheck` when long.
- Stale prose (plan E): `templates/TASK.md:21-25` · `SOLO.md:116-117`, `PROTOCOL.md:117-118` ·
  `SOLO.md:22`, `kit/CLAUDE.md:22-23`, `PROTOCOL.md:130` (triage does not read `publish:`) ·
  `kit/CLAUDE.md:96-97` · `PROTOCOL.md:350`. `route.sh:220` is T-321's.
- Headings: no existing heading is renamed; the only new ones are PLANNER's above and PROTOCOL's
  `## AWAY RUNS — budgets, the pulse, parked` (both api-kit rows, re-pinned by T-325).
### 8.4 Release (T-327)
`kit/ops/VERSION` → `version: 6.20.0`; `CHANGELOG.md` `## 6.20.0` — measured claims only (the plan's
diagnosis, T-322's and T-326's numbers, which tail was or was not built), naming every card.

## § 9 Spec sections this plan appends (same text, never edits)
bg-jobs v3 · role-handover v5 · away v2 · run-finish v4 · keep-awake v2 · test-depth v3 ·
express-lane v3 · test-surfaces v3 · save-hops v3 · model-routing v5 · module-layout v10 — each a
short `## vN` pointing here.

## § 10 Joined-tree goldens — which run the real thing, and who runs them
Seams between side-by-side wave-1 cards, proven only on the joined tree, by **T-327**:
- **`away-run`** (NEW, T-327): fixture repo with a board; `presence-guard.sh` fed an ExitPlanMode
  PostToolUse payload with mode `auto` → armed file (T-319); `bg run hang --budget 2 -- <a shell that
  spawns a sleeping child>` → `bg wait hang --max 60` exit 4, the pinned line, no surviving child
  (T-318); `handover-hook.sh --test stop` with work left → `block:run`, three times → `allow:stalled`
  (T-319); `defer` one command, then `finish` → `finish: parked - 1 waiting on you`, one ⛔ line, armed
  file gone (T-324); `pulse` → `parked` (T-318).
- **`runner-path`** (NEW, T-327): `route --role RUNNER` prints `agent: polaris-runner` (T-321);
  model-guard fed a spawn with `subagent_type: polaris-runner`, `model: haiku` → allowed; a runner
  call `bash ops/polaris bg wait x --max 240` → allowed; `ls` → blocked; a non-runner Haiku session →
  today's block line (T-320); the runner's reply contract checked against a green and a red job's
  `bg wait`/`bg tail` output.
- **T-327's last step** runs side by side on the joined tree: `away-run`, `runner-path`, `api-kit`
  (re-pinned to exactly § 0's names and § 8.3's headings), `lib-census`, `startup-budget`,
  `keys-drift`, `bg-lifecycle`, `bg-budget`, `pulse-run`, `heavy-slot`, `lease-token`, `handover-route`,
  `handover-stop`, `stop-away`, `stop-question`, `run-caps-plan`, `presence-guard`,
  `presence-installed`, `permission-hook`, `awake-hook`, `model-guard-v2`, `route-tier`, `test-depth`,
  `depth-ui`, `depth-stamp`, `qa-stamp`, `express-pr`, `express-ui`, `flow-solo`, `wrap-own-folder`,
  `self-land-finish`, `finish-blocked`, `finish-parked`, `depth-metrics`, `heal-model-line`,
  `heal-design`, `install-update`, `output-style-installed`, `plain-voice`, `speed-report`,
  `speed-plan`, `new-task`, `pack-guides`, `pack-steps`, `pack-visual`, `pack-named-tests`. A red is
  re-pinned by T-327 only when the diff is exactly what this contract says the joined tree prints;
  anything else → hand back.
- Wave-1 cards keep `lib-census` in `verify:`; T-319, T-320, T-321, T-322, T-328 also keep `api-kit` (proof
  they add no public name). `cli-help` is re-pinned after the dogfood. The CI self-test is the
  conductor's release ritual, not a card.

## Executable checks (per card; each card's `verify:` names them)
- T-318: `bg-lifecycle` (existing lines byte-identical; appended: exit 4 after a `--budget 2` hang,
  `--steps` stops at the first red, `--done`, `bg reap` silent when nothing to reap) · NEW `bg-budget`
  (budget from `.prev`, from class, from last-suite-seconds, floor; a grandchild-spawning hang leaves
  no process — `ps` checked by command marker; retried once; rc 124 + overrun) · NEW `pulse-run`
  (`ok` unarmed; armed `act`, `parked`, `done`; `--reenter` count and refusal; `preflight` lines on a
  fixture with no remote; `defer` usage and write) · `heavy-slot`, `lease-token` (armed: `queued:` at
  once; unarmed byte-identical) · `handover-route` (`dead:`/`crashed:` lines) · `startup-budget`
  (re-pinned) · `lib-census` · `api-kit` (re-pinned: § 0's six names).
- T-319: `presence-guard` (appended: armed written on approval with the slug, removed on plan mode;
  re-entry prefix under `reentry: desktop` only) · `stop-away`, `handover-stop`, `stop-question`,
  `run-caps-plan` (existing lines byte-identical; appended rung cases) · NEW `permission-hook` · 
  `awake-hook` (appended: armed = active, reap call, stalled marker) · `install-update`,
  `presence-installed` (the four new registrations merge once, re-run idempotent) · `api-kit` · `lib-census`.
- T-320: `model-guard-v2` (existing lines byte-identical; appended runner cases incl. the
  regex's edges: `bg wait x --max 240` ok, `bg wait x; rm -rf .` blocked, `bg run` blocked, `-n 15`
  ok) · `machine-armed`, `update-arms` (agents copied, idempotent) · `api-kit` · `lib-census`.
- T-321: `test-depth`, `depth-ui`, `depth-stamp`, `qa-stamp`, `route-tier` (RUNNER lines) ·
  `related-tests`, `change-bound` (an edited test is never small) · `verify-stamp` (freshness skip) · `api-kit` · `lib-census`.
- T-322: `bash -n kit/ops/bench.sh` · `bash kit/ops/bench.sh --flow --runs 1` prints every phase line
  and the `flow:` line · `api-kit`. BEFORE numbers in Notes (best of 3).
- T-328: `flow-solo`, `wrap-own-folder` (`begin -`, wrap commits owned files, the reach line under
  begin) · `pack-steps`, `pack-guides`, `pack-visual`, `pack-named-tests`
  (forecast only where none/look/ui) · `landed-seal`, `self-land-finish`, `hops-due`, `tune-report`
  (once per landing) · `lib-census` · `doctor --fast`.
- T-324: NEW `finish-parked` (parked token + lines + rc 1 + armed removed; `run:` line on an armed rc
  0; unarmed byte-identical; armed off-base merged → switched) · `finish-blocked`, `finish-qa-red`,
  `depth-metrics` · NEW `express-ui` (`land --express` at ui runs lint+typecheck only, the skip line
  once) · `express-pr` · `lib-census` · `doctor --fast`.
- T-325: `heal-model-line`, `heal-design` (old 🚩 two lines and old model line migrated, exact match
  only, CRLF kept, an edited line untouched) · `plain-voice`, `output-style-installed`,
  `speed-report`, `speed-plan` · `api-kit` (re-pinned: § 8.3's two headings).
- T-326: the trigger numbers in Notes; if built, `flow-solo`, `self-land-finish`, `wrap-own-folder`
  and `bench.sh --flow` AFTER numbers.
- T-327: § 10.

## Invariants
- Unarmed, every command, hook and golden behaves as 6.19.0 (the armed-only rule).
- Only budgets kill; `pulse`, keep-awake and the Stop gate report, reap through `bgwatch_reap`, never
  kill by name or across cwds.
- The Haiku exception is exactly one agent type and one command regex; Haiku stays denied for every
  other session, spawn, switch and config key.
- `finish` rc semantics are unchanged: 0 only when the run is truly over; `parked` is rc 1.
- No PermissionRequest path ever allows on the user's behalf.

## Changelog
- v1 2026-11-24: created for T-318–T-327 (plan walk-away, kit 6.20.0); before any claim T-323 was
  re-filed as T-328 without author.sh (a glob-vs-glob false overlap with T-320 had chained it).
