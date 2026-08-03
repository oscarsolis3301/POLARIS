# CONTRACT: bg-jobs            (v1 — 2026-08-03)
Owned by the Planner. Builders code against this and never invent beyond it.
Append-only once any dependent task is claimed: breaking changes = new `## v2` section + a migration task.

## Purpose
The harness caps a foreground tool call at 600s (600000ms). MEASURED on this repo: full selftest
805s serial · 169-330s sharded `--parallel 3` (25 drills) · `test_fast` 320s · the whole `qa` loop
1225s. So suite-length commands time out, return NOTHING, and get re-run — three sprints of
log-and-poll ceremony, and two subagents last sprint ended turns with a suite still running. `bg`
makes the recipe a command: run detached, keep working, collect in bounded chunks. Tasks: T-070
(module) · T-065 (finish guard) · T-066 (PROTOCOL § LONG COMMANDS) · T-067 (hook) · T-068/T-069
(role pointers) · T-071 (drill + golden).

## Interface — the job registry (dir-per-job)
`$PRIMARY/.polaris/bg/<name>/` — ALWAYS under the PRIMARY checkout (one registry every session and
worktree sees), regardless of the caller's cwd:
- `cmd` — the exact command line run
- `cwd` — absolute dir it executes in
- `pid` — the detached runner's pid, written at spawn (pid semantics from birth — the T-064 lesson)
- `log` — combined stdout+stderr, append-only
- `rc` — written LAST, on completion: the command's exit code. Its EXISTENCE means "finished".
- `start` / `end` — epoch seconds
`<name>` grammar: `[A-Za-z0-9._-]+` — anything else ⛔ rc 1. A completed same-name job auto-rotates
to `<name>.prev` (ONE slot per name, archive-not-delete) before a new run starts; `sweep --fix`
rotates any job whose `start` is older than 24h. The registry is runtime state: `.polaris/` is
already gitignored — never tracked, never a board file.

## Interface — the commands (`kit/ops/lib/bg.sh`, dispatched by `kit/ops/polaris`)
`bg run <name> [--force] [-- <cmd…>]`
- A bare SUITE-KEY name runs that CONVENTIONS value: `test` `test_fast` `lint` `typecheck` `build`
  `uat` execute in the CALLER's cwd — a builder proves its own worktree; `qa` ALWAYS executes in
  the primary (it stamps `.polaris/suite-stamp` there, so a green `bg run qa` on a clean tree makes
  a later `finish` skip the whole suite via the EXISTING fast path — zero new code, that is the
  point). Empty/missing CONVENTIONS key → ⛔ rc 1.
- `-- <cmd…>` runs an arbitrary command under that name, in the caller's cwd.
- Same name already RUNNING (no `rc`, pid alive) → ⛔ rc 1 naming `bg status <name>`; `--force`
  best-effort kills it, rotates, starts fresh. The runner's stdin is `/dev/null` and it survives
  the parent tool call ending (a tool call must be able to return while the job runs).

`bg status [<name>]` — rc-FILE-FIRST, then the pid, never the reverse:
- `rc` exists → the job's verdict: content `0` → exit 0 (green) · anything else → exit 1 (red)
- no `rc`, `kill -0` pid alive → exit 2 (running)
- no `rc`, pid dead → exit 3 (unknown: crashed — or a Windows pid was reused; SAY so and name the
  log. Honesty over pretense: pid-reuse cannot be solved in bash, only ordered around, which is
  what rc-file-first does.)
- No `<name>`: one line per job dir (name · verdict word · age); no jobs → `no background jobs`, rc 0.

`bg tail <name> [-n N]` — last N (default 20) log lines. Read-only.

`bg wait <name> [--max <s>]` — poll ~2s with occasional progress notes; `--max` DEFAULT 300 —
deliberately half the 600s cap, so agents collect in bounded chunks. Finished → print the last log
lines + verdict and exit with the job's rc (0/1). Still running at `--max` → ONE
`still running — bash ops/polaris bg wait <name>` line, exit 2. Chunk-resumable, NEVER a question.

Permissions: read-only forms (`bg status` · `bg tail` · `bg wait` · `route`) get readonly-allow.sh
auto-approval (T-067) so they pass inside compound commands; `bg run` mutates (spawns + writes the
registry) and keeps its prompt there — bare `bash ops/polaris bg run …` is already covered by the
kit's standing settings.json allow rule.

## finish gains a bg guard (T-065, `cmd_finish` in observe.sh)
Any job dir with NO `rc` file → one pending line:
`background job <name> still running — collect it: bash ops/polaris bg wait <name>`
(dead-pid unknowns phrase it `crashed?` and name `bg status <name>` instead). Invariant 4 stays
absolute: `bg wait` returns 0 for YOUR suites BEFORE handoff/land/seal/finish.

## Doctrine — `PROTOCOL.md § LONG COMMANDS` (T-066 writes it; the never-written recipe, once)
Pinned content: the measured table above, then three bands — under ~60s: plain foreground · 60s to
the cap: foreground WITH an explicit tool timeout ≥ the measured time (a defaulted timeout is how
suites die at 120s) · past the cap: `bg run <key>`, keep working, chunked `bg wait` · the SUBAGENT
rule: NEVER end a turn with your job still running — your existence ends with the turn, and
completion notifications reach only the TOP-LEVEL session, so a subagent polls inside its turn ·
top-level sessions may use the harness's native run_in_background instead · sharded
`doctor --selftest --parallel 3` fits the cap (169-330s) while serial (805s) and `qa` (1225s) do
not. The canonical pointer line, VERBATIM — CONDUCTOR carries it at all five kickoff sites (T-068),
BUILDER/SOLO/INTEGRATOR/PLANNER once each (T-069); parallel wording lanes agree by pinning:
> Long command? `ops/PROTOCOL.md` § LONG COMMANDS: foreground with an explicit timeout ≥ the measured time; past the 600s cap → `bg run` + chunked `bg wait`. A subagent never ends its turn with a job still running.

## Module census (module-layout v4 pairs with this)
bg.sh top-level fns are `bg_`-prefixed plus `cmd_bg` as the dispatcher. INTENDED census: `cmd_bg`
`bg_run` `bg_status` `bg_tail` `bg_wait` `bg_rotate` `bg_resolve` `bg_alive` — ≤10 total; the
landed api-kit delta is authoritative on the final list, and T-070 owns that golden's wave-2 delta
(one line per fn, by the T-062 recipe). Loader: the FULL-load `_mods` list gains `bg` immediately
after `admin`; the `_match|_rules|_guard` guard path stays EXACTLY `core ownership`. bg.sh ≤ 300
lines, function definitions only (module-layout invariants).

## Executable check
- `bash kit/ops/polaris bg run demo -- true` → rc 0; `bg wait demo --max 60` → rc 0; `bg status demo` → rc 0
- `bash kit/ops/polaris bg run demo2 -- false`; `bg wait demo2 --max 60` → rc 1 (red is honest)
- a re-run of a finished name rotates it: `.polaris/bg/demo.prev/` exists in the primary
- T-071's `ops/tests/bg-lifecycle.cmd` proves green/red/duplicate-refusal/tail/rotation from a
  FIXTURE repo (hermetic; fast commands only — `true`/`false`/`echo`, never a real suite).

## Invariants
- rc-file-first, ALWAYS: a pid check alone never declares a verdict (Windows pid reuse).
- Rotation archives; it never deletes the just-finished job. One `.prev` slot per name.
- No lock files: the registry is per-job-dir; two `bg run` of DIFFERENT names never interact.
- `bg` never writes the board, EVENTS.ndjson, or any lock — workspace machinery, like park.
- bash 3.2 + Git Bash: no mapfile, no assoc arrays; the detach survives the parent shell exiting.

## Example
A Builder on a 5-pt task, in its worktree: `bash ops/polaris bg run test_fast` → keeps editing →
`bg wait test_fast` (one 300s chunk) → rc 0 → handoff. An Integrator at a wave gate: `bg run qa` →
drains review/ meanwhile → `bg wait qa` twice → green stamps `.polaris/suite-stamp` → `finish`
skips the re-run.

## Changelog
- v1 2026-08-03: created for T-065, T-066, T-067, T-068, T-069, T-070, T-071 (plan: routing-and-bg)
