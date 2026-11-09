# Minutes, not hours — finish 6.13.0, then make POLARIS fast everywhere

## Context

You asked why the remaining work was quoted at four hours, and said hours are unacceptable in this
project and every other. I measured where the time goes before designing anything. The slowness is
not the protocol's idea (disjoint files, parallel builders). It is six specific things, each
measured below, and none of them is your code being tested.

**Your decisions (2026-11-09):**
- Helper agents are **sized to the task**: small mechanical work on Sonnet at low effort, normal
  tasks on Opus at medium, big or risky tasks plus planning and landing on Opus at high.
- The release check **proves the published bytes match** the proven code, and you want this update
  to be **aggressive**: change, replace or remove whatever makes POLARIS slow.
- An update **commits itself and fans out** to every other idle POLARIS project on this PC.
- Earlier today: Fable is yours to pick again; routing never picks it; Haiku stays blocked.

### What I measured (this PC: 16 cores, 48 GB; sprint 21's own transcripts and board events)

| # | Finding | Measured | Fix |
|---|---|---|---|
| 1 | Tasks wait to land far longer than they take to build | built in 22 min, then **80 min** from "built" to "done" (last 40 tasks) | Phase 2 pipelines landing; Phase 3 lets every task land itself |
| 2 | The full suite blocks every wave, and this PC is the slow place to run it | 48–53 min per wave here. The **same** self-test takes **166 s on CI's Linux**, 300 s on macOS, 1,059–1,308 s on CI's Windows | CI becomes the self-test's judge (§1.3) |
| 3 | The goldens run one at a time | 1,478 s serial. All 68 at once, 12 wide: **406 s, 68 green, 0 red** | built-in parallel `check` (§2 A) |
| 4 | More shards do not help the local self-test | 3 shards ≈ 15 min, 10 shards = 13 min (each shard repeats a 1–2 min setup) | stop running it locally; see 2 |
| 5 | **Every helper ran on Opus at MAX effort**, inherited from the chat | a one-line version bump: 73,000 output tokens, 8 min. Thinking was 50–72% of every builder's and the planner's time | sized helpers (§2 E, and by hand from Phase 1) |
| 6 | The release check repeats CI | 37 min serial self-test of the installed copy | byte-identity check, ~1 min (§1.2) |
| 7 | Sealing rebuilds the knowledge base every time | **20 s** in a 124-file repo with nothing else to do; 136 s per seal here. ~600 process starts in one loop | single-pass rebuild (§2 C) |
| 8 | One small change costs ~10 separate commands | 98 s of pure command time in a tiny repo with a 1-second test suite, before any thinking | two composite commands (§2 G) |
| 9 | The end of a run stalls on housekeeping | both sprints ended red on "lessons list too long" and needed a hand fix | advisories never block (§2 D) |
| 10 | Your other projects are stale, and updates leave files uncommitted | The Director 6.7.1 with 64 uncommitted files; job, venzeti, pip on 6.10.0 | commit + fan out (§2 F) |

Not the problem (measured, so nobody "fixes" them): the per-call guards cost 73–340 ms; single
commands cost 1–5 s; `integration: paranoid` in three of your projects is read by no code.

**What "minutes" means after this plan** (targets, each checked in Verification):
- A one-line change in any project: about 3 minutes, start to proven.
- A normal 3-point task: about 10 minutes.
- A wave in this repo: landed within ~5 minutes of the last lane finishing; full proof ~7 minutes,
  never blocking the next wave.
- A release: about 15 minutes from sealed to published, installed and pushed.
- A 12-task plan like sprint 21: about 80 minutes instead of 10 hours. Multi-task plans are bounded
  by the longest chain of dependent tasks; this plan cuts everything around the building.

**On "if this can't be done as a skill".** POLARIS is not held back by being a skill: the skill only
triggers it, and the work is done by commands, role files and hooks. Rewriting it as a plugin or a
server would change none of the ten findings above (single commands are already 1–5 s). What helps
projects most is what this plan does: commands do the waiting instead of agents, helpers are sized
by the kit itself, proof runs where it is fast, and one update covers the whole PC.

---

## Phase 1 — ship 6.13.0 today (about 55 minutes)

State: sprint 21 is sealed (main 4c0e07d, tag sprint/21). CI is green on Linux, macOS and Windows;
only the version job is red because v6.13.0 is not tagged. T-270 (Fable) is in review/ and must not
land as it is.

### 1.1 T-270 gets its missing half (kickback → same task)
`polaris update` never refreshes the machine's guard, so a PC that only ever updates would keep
blocking Fable. The fix must live in `kit/ops/install.sh`, because the OLD updater's code is what
runs during the first jump and `install.sh` is the only new code it executes.
- Conductor: add the behavior below to `ops/contracts/speed.md` § 2b first. Then
  `bash ops/polaris kickback T-270 -m "<why>"` (review → active; its lock and worktree are kept),
  then three `grant` calls, one path each (`grant` takes one path and needs a claimed task):
  `kit/ops/install.sh`, `ops/tests/update-arms.cmd`, `ops/tests/update-arms.expected`. A fresh
  builder re-enters with `bash ops/polaris resume T-270`.
- `kit/ops/bootstrap.py`: move the one-time restore out of `merge_model_guard` into a module-level
  `restore_fable_once()` (no arguments, returns True when it changed the list, never raises, prints
  nothing). `merge_model_guard` calls it and prints its existing ✅ line on True. The module must
  stay import-safe (`pack.py` already imports `find_bash` from it).
- `kit/ops/install.sh`, updater path only (`POLARIS_SHA` is set, as T-260 established), after the
  kit files are copied and before `heal`. Silent, fail-open, never registers anything new:
  1. If `$HOME/.claude/polaris/model-guard.sh` exists and differs from `$KIT/ops/hooks/model-guard.sh`,
     copy the new one over it and `chmod +x`.
  2. If `$HOME/.claude/settings.json` mentions `model-guard.sh` (the guard is registered), python is
     available and `$KIT/ops/bootstrap.py` exists, run
     `"$PY" -c 'import sys; sys.path.insert(0, sys.argv[1]); import bootstrap; bootstrap.restore_fable_once()' "$KIT/ops"`.
- Golden `update-arms` (fake HOME **and** USERPROFILE, never the real `~/.claude`): old guard +
  registered + list without Fable → guard bytes equal the kit's, list gains `fable` once, marker
  written; second run changes nothing; no guard file → nothing created; guard present but
  unregistered → script refreshed, list untouched; no `POLARIS_SHA` → nothing happens.
- Unchanged: `install-update` and `machine-armed` stay green; install output gains no line (the two
  installer tripwires: lines above `▶ NEXT`, and never the INIT kickoff phrase).

### 1.2 New task — the release check proves bytes (2 pts, `kit/ops/pack.py`)
`dogfood()` (about line 210) today installs the published zip and runs the serial self-test.
- Packing is already deterministic ("the same commit always packs to the same bytes", pack.py about
  line 130). Move the loop that builds `entries` into a function, `build_entries()`, used by both
  the packer and the dogfood.
- After the version check and BEFORE installing: compare the downloaded zip's members with
  `build_entries()` from this working tree — same member names, same bytes. One exemption:
  `ops/VERSION` compares with its two stamped lines (`commit:` and `built:`) removed from both
  sides, so a later docs-only commit on main cannot fail the check. Any other difference: stop,
  repo untouched, name the first differing member.
- Then install as today, then run `ops/polaris doctor --fast` (not `--selftest`). `--dogfood --full`
  keeps the old serial self-test on demand.
- Final line: `✅ POLARIS <v> installed from the published release — same bytes CI proved, and the quick check passes.`
- Golden `dogfood-bytes`: a local `file://` zip built by `pack.py` in a scratch clone passes; the
  same zip with one byte changed in one member is refused before install.

### 1.3 New task — CI is the self-test's judge (2 pts, new file `tools/proof.sh`, this repo's own tool)
The script is the whole proof for one commit, and overlaps the two halves:
1. `sha=$(git rev-parse HEAD)`. Look for an existing CI run:
   `gh run list --workflow ci.yml --commit "$sha" --json databaseId,status,conclusion --limit 5`.
   None → `git push -q origin "$sha:refs/heads/proof/${sha:0:12}"`, then
   `gh workflow run ci.yml --ref "proof/${sha:0:12}"`, then poll the same listing (every 5 s, up to
   90 s) for the run id. At start, delete other remote `proof/*` branches.
2. While CI runs, run the goldens here, 12 at a time:
   `ls ops/tests/*.cmd | sed 's|.*/||; s|\.cmd$||' | xargs -P 12 -I{} bash kit/ops/polaris check --only {}`
   (task A later replaces this line with `bash kit/ops/polaris check`).
3. Wait for the job named `ubuntu-latest` (`gh run view <id> --json jobs`, every 15 s, 20-minute
   cap). Green goldens AND a green Linux job → rc 0. Red Linux job → print the last 40 lines of
   `gh run view <id> --log-failed`, rc 1.
4. Write `.polaris/ci-proof` = `<sha> <run-id>`. `tools/proof.sh --await macos-latest` waits for that
   job of the recorded run; `--report` prints every job's state.
5. No `gh`, no network, or a failed dispatch → say so in one line and fall back to
   `bash kit/ops/polaris doctor --selftest --parallel 3` plus the goldens.
- The version job fails on a proof branch whenever VERSION is ahead of the newest tag. That is
  expected; the script reads job results by name and ignores that job.
- Verify lines stay narrow: `bash -n tools/proof.sh` and a golden that runs the script with a stub
  `gh` on PATH (green, red and missing-`gh` paths).

### 1.4 Run order
1. Conductor edits (board quiet, main): record your decisions in `ops/CONVENTIONS.md` —
   `model_strong: opus`, `model_mid: opus`, `model_cheap: sonnet` (so no helper inherits Fable), each
   with a dated owner comment. File the two new tasks with `bash kit/ops/polaris new`.
2. Three builders in parallel, sized by hand from `route`: T-270 rework (Opus, high), the release
   check (Opus, medium), `tools/proof.sh` (Sonnet, low).
3. One integrator (Opus, high) once all three are in review: land all three, run each task's
   verify lines on the wave tip, seal, `done`. **No full `qa` in this step.**
4. Conductor: set `test: bash tools/proof.sh` and remove `uat:` in `ops/CONVENTIONS.md`; rewrite the
   Release ritual there (step 4 = the byte check; new step 0 = `finish` green, which now includes
   CI's Linux run; tag only after `tools/proof.sh --await macos-latest` is green). Then
   `bash ops/polaris finish` in the background: this is the gate.
5. Tag `v6.13.0`, push the tag, wait for `releases/latest`, `python kit/ops/pack.py --dogfood`,
   `polaris version`, `check --update --only cli-help`, the installed-copy goldens in parallel,
   commit "Dogfood 6.13.0 …", push.
6. Machine check: `availableModels` holds `fable`; a Fable payload passes the guard and a Haiku one
   is refused; heal rewrote this repo's CLAUDE.md model line.
7. Update checks on the practice shops and the test repo (6.11 → 6.13 shows the new installer's
   save-hops line once; 6.12 → 6.13 shows 6.12's own; no settings churn).
8. The live tidy proof on the 6.12 shop (one TIDY helper, Opus medium) while the final `finish`
   runs. The lookup benchmark still waits for your `claude` `/login`.

---

## Phase 2 — the speed release, 6.14.0 (about 75 minutes)

Landing stays on the integrator for this phase, but each wave now costs ~5 minutes: land, verify
lines, seal, then `bg run qa` starts in the background and the next wave is promoted at once. A red
background proof becomes a fix task before `finish`. Eight tasks, three waves.

### Wave 1 (four lanes, no shared files)

**M — `observe.sh` becomes five modules, move-only (5 pts).** It is 3,267 lines and four of this
phase's tasks need it, which would force a serial chain.
- New files under `kit/ops/lib/`, functions moved with their leading comments, bodies untouched:
  - `drift.sh`: `pat_overlap`, `rules_gate`, `dep_ids`, `dep_reaches`, `cmd_drift`, `cmd_rules`,
    `surfaces_health`, `cmd_surfaces`, `surfaces_apply`.
  - `check.sh`: `scaffold_try`, `scaffold_dirs`, every `harness_*`, `cmd_harness`, `cmd_scaffold`,
    `cmd_check`.
  - `route.sh`: `cmd_triage`, `cmd_route`, `depth_line_say`, `uat_deferred_say`, `cmd_depth`.
  - `qa.sh`: `cmd_qa`, `cmd_finish`.
  - `observe.sh` keeps the rest (status, sweep, doctor, metrics, why, dash, fleet, notify-gate).
- The loader in `kit/ops/polaris` sources the four new modules; `ops/contracts/module-layout.md`
  gets v7; `ops/tests/api-kit.expected` is re-pinned by this task alone (rows move files, no row
  appears or disappears).
- Proof of "move-only", in the task's verify: a script lists every top-level function in
  `kit/ops/lib/*.sh` as `name` + body hash before and after; the two lists must be identical as
  multisets. Plus `bash -n` on each file and `doctor --fast`.

**C — the knowledge base rebuilds in one pass (3 pts, `kit/ops/lib/knowledge.sh`).**
`brain_code_map` (about line 346) loops per folder with a dozen pipelines each.
- Rewrite as: ONE `git ls-files`, ONE symbol grep over all tracked files (through `xargs -0`), ONE
  `LC_ALL=C` awk that groups by folder and prints the same line shapes (`## <dir>/`, `- files:`,
  `- purpose:`, `- symbols:`, `- hotspot:`). Purposes still come from `guide_purpose` and README
  headings, read only for folders that have one.
- Pin the ordering in the contract: folders in C byte order; top three extensions by count, ties by
  extension ascending; first twelve symbols in C byte order, unique.
- Every brain file is written to a temp name and moved into place.
- Golden `brain-codemap` pins the exact output on the practice shop; the `brain` drill stays green.
- Target: under 3 s on the shop (20 s today), under 10 s here.

**F — one update covers the PC (5 pts, `kit/ops/lib/admin.sh`, the `autoupdate` drill in
`kit/ops/lib/selftest/remote.sh`, goldens).**
- **Self-commit.** After `update` or `update --auto` applies: commit exactly the kit paths the update
  changed, subject `chore(polaris): POLARIS <old> → <new>`. Only when ALL hold: HEAD is on `<base>`;
  no merge or rebase in progress; nothing was staged before; `publish:` is not `pr`. Otherwise
  today's "nothing was committed for you" note, unchanged. Files that were dirty before the update
  are handled exactly as today (parked or left alone) and never enter the commit. Never pushes.
- **Fan-out.** A typed `update` (not `--auto`, `--all` or `--repo-only`) ends by starting
  `update --all` detached, logging to `~/.claude/polaris/update-all.log`, and prints one line:
  `updating <n> other projects on this PC in the background — see <log>`. `--all` keeps its rules
  (quiet boards only, one line per project) and each project it updates self-commits by the rule
  above.
- **`speed` shows the result:** two new lines from `EVENTS.ndjson`, last 20 finished tasks:
  `build: median <m> min` and `built → done: median <m> min`.
- No new CONVENTIONS key. Drill cases: self-commit on base; refused on a feature branch, with staged
  work, and under `publish: pr`; the fan-out line; `--auto` never fans out.

### Wave 2 (four lanes, after M lands)

**A — goldens run side by side (3 pts, `kit/ops/lib/check.sh`, `tools/proof.sh`).**
- `check [--only <glob>] [--update] [--jobs <N>]`. Default N = cores (first of
  `getconf _NPROCESSORS_ONLN`, `nproc`, `sysctl -n hw.ncpu`, else 4), capped at 12;
  `POLARIS_CHECK_JOBS` overrides. `--update`, N = 1, or a single selected golden → today's serial
  loop, byte for byte.
- N workers, each a background subshell running its share one after another. Shares are dealt
  longest-first from `.polaris/check-times` (`<name> <seconds>`, rewritten after each run; unknown =
  20) by one awk call. No `wait -n`, no arrays (bash 3.2).
- Each golden's stdout and exit code go to temp files; after `wait`, results print in today's order
  with today's exact lines, so nothing that pins `check` output moves.
- A golden that is red beside others is re-run once alone before it counts. Green alone → it counts
  green, plus one line: `   note: <name> passed alone but not beside others — it shares state with another golden`.
- Golden `check-parallel`: six tiny goldens in a scratch repo (one red, one with an `.rc`, two that
  log start and end times); `--jobs 3` and `--jobs 1` print identical output; the logged intervals
  overlap under 3 and never under 1.
- `tools/proof.sh` step 2 becomes `bash kit/ops/polaris check`.

**D — the end of a run never stalls or pays twice (5 pts, `kit/ops/lib/qa.sh`, `drift.sh`,
`builder.sh`, `integrate.sh`, `kit/ops/roles/INTEGRATOR.md`, the `drift`/`qa`/`finish` drills in
`kit/ops/lib/selftest/policy.sh`).**
- **Housekeeping is advice.** The "doc overflow" findings (Learned over 5 bullets, MAP over its cap)
  print as `advisory:` lines, are never counted, never turn `drift --strict`, `qa` or `finish` red,
  and never withhold the suite stamp.
- **Verify once.** A green `verify` writes `.polaris/verify-stamp/<ID>` (HEAD sha). `handoff` skips
  re-running the verify COMMANDS when the stamp equals HEAD and the worktree is clean, printing
  `verify: proven at <sha7> — not re-run`; ownership, rules, surfaces and freshness gates still run.
  `run-verify` skips when the landed commit's tree equals the feat tip's tree, printing
  `run-verify: same tree the builder proved — not re-run`.
- **A self-landed lane ends clean.** Golden: claim → edit → handoff under `landing: self` → `finish`
  exits 0 with no manual `sweep`. Fix whatever makes it red, if anything does.
- INTEGRATOR.md: section 3 no longer tells anyone to type `git checkout -b` (the guard refuses it;
  `land` creates the wave branch); waits say `bg wait --max 120`; the wave gate is the tasks' verify
  lines, and the full proof runs in the background after the seal.

**E — helpers are sized by the kit (5 pts, `kit/ops/lib/route.sh`, `kit/ops/KEYS.tsv`,
`kit/ops/roles/CONDUCTOR.md`, `kit/ops/roles/PLANNER.md`, `kit/ops/roles/EVOLVE.md`,
`kit/ops/PROTOCOL.md`, `ops/contracts/model-routing.md`, goldens `route-tier`, `keys-drift`).**
- `route` line 1 is unchanged (the tier word). Two notes now always follow unless disabled:
  `   model: <name>` and `   effort: <level>`.
- Defaults in code (an update never rewrites a project's config): cheap → `sonnet` / `low`;
  mid → `opus` / `medium`; strong → `opus` / `high`. Keys `model_cheap|mid|strong` (existing) and
  `effort_cheap|mid|strong` (new) override; the value `inherit` drops that note. `model_denied`
  (Fable, Haiku) is untouched: routing still never names either.
- The effort note is clamped to the chat's own level when
  `~/.claude/polaris/model-state/$CLAUDE_CODE_SESSION_ID.effort` exists.
- CONDUCTOR.md: every spawn passes both notes as the spawn's `model` and `effort`. A kicked-back
  task is retried one effort level higher. EVOLVE is spawned only when the run had a kickback, a
  blocked task, a red proof or more than five Learned bullets; otherwise one line says it was
  skipped.
- PLANNER.md: verify lines name the narrowest proof; `doctor --fast` only for tasks that change
  `kit/ops/polaris` or `kit/ops/lib/`; never a check `handoff` already runs.
- PROTOCOL.md § MODEL ROUTING states the new defaults; § LONG COMMANDS says `--max 120`.

**G — one call in, one call out (3 pts, new `kit/ops/lib/flow.sh`, `kit/ops/polaris`,
`kit/ops/roles/SOLO.md`, `kit/ops/roles/BUILDER.md`, `ops/tests/api-kit.expected`,
`cli-help-parity`).**
- `polaris begin <draft.md>` = `new` → `triage <ID>` → (line 1 must be `solo`, else print triage's
  answer and exit 3 with the task left in ready/) → `claim` → `pack`. One call.
- `polaris wrap [<ID>]`, from the task's worktree = `handoff` → (under `landing: integrator`, for a
  solo task: `land --express <ID>` from the primary) → `next`; when its line 1 is `finish`, run
  `finish` and exit with its code; otherwise print that line.
- Both only call existing commands in order; no gate changes. SOLO.md uses the two commands;
  BUILDER.md drops the separate `verify` before `handoff`.
- This task owns `kit/ops/polaris`: the dispatch and help for `begin`/`wrap`, plus the help lines for
  A (`--jobs`) and E (the two route notes), each pinned byte-exact in the contract.
- Golden `flow-solo`: a scratch repo goes from draft to `done/` and a green `finish` in two calls.

### Wave 3
**R — Release 6.14.0** (1 pt, `kit/ops/VERSION`, `CHANGELOG.md`), then the ritual from 1.4 steps 4–5,
then `bash ops/polaris update --all` from this repo so The Director, job, venzeti and pip move to
6.14.0 and commit themselves. Report each project's line.

---

## Phase 3 — nothing waits to land, 6.15.0 (about 75 minutes)

The queued safe-landing work (T-221…T-227, `ops/contracts/safe-landing.md`) is what makes parallel
self-landing safe, and self-landing is what removes finding 1 for good.
1. Conductor: move T-160 and T-232 from blocked/ to done/ with one board commit (both shipped by
   hand weeks ago; T-227 depends on T-232 and could never promote).
2. One planner pass (Opus, high) re-grooms T-221…T-226 against the code as Phases 1–2 left it
   (T-259 and task D changed `integrate.sh` and `builder.sh`; `observe.sh` is now five files), and
   retitles T-227 to 6.15.0. The chain T-222 → T-223 → T-224 → T-225 stays serial (shared files).
3. Build and land the chain; T-226 (prose) runs beside it.
4. Conductor: delete the `landing: integrator` line from `ops/CONVENTIONS.md`. From here every task
   lands itself at handoff and the last lane out seals.
5. Release 6.15.0 by the same ritual, then `update --all` again.

---

## Rules every builder in this plan follows (each one has cost a release before)
- macOS runs bash 3.2: no `case` inside `$(...)`, no `${v,,}`, no `wait -n`, no associative arrays.
- A fork costs 30–50 ms here: never fork per line or per item; one awk beats a loop.
- Tests fake HOME **and** USERPROFILE together and never touch the real `~/.claude`.
- New names are private (`_name`) unless the task says it owns `ops/tests/api-kit.expected`.
- The installed `ops/` is old until the dogfood: verify lines use `bash kit/ops/polaris …` and
  `POLARIS_ROOT=$PWD python kit/ops/index.py …`.
- Install output: nothing new above `▶ NEXT`; never the INIT kickoff phrase.
- The primary checkout is guarded: no `git checkout`, `reset`, `merge` or branch deletion typed from
  it. A guard refusal is handed back, never worked around.
- Never edit `kit/ops/polaris` or `kit/ops/lib/*.sh` in the primary while a suite runs.
- Commit messages are plain and friendly, with no attribution lines.

## Verification
1. **Phase 1:** `releases/latest` = v6.13.0; CI green on all four jobs for the dogfood commit;
   switching to Fable works and a Haiku session is still refused; `update-arms` green; the live tidy
   pass lands with none of the 17 old workarounds.
2. **The suite is fast:** `tools/proof.sh` on a clean HEAD finishes in under 8 minutes with both
   halves green; `check` on all goldens under 7 minutes with the same output as `--jobs 1`.
3. **The ceremony is short:** the timing script I used for finding 8 (kept in the scratchpad as
   `bench4`) is re-run on the practice shop after Phase 2: `begin` + `wrap` total under 45 s
   (98 s today), with a seal under 10 s.
4. **Helpers are sized:** in the Phase 2 transcripts, a 1-point task shows `sonnet` and `low`, a
   3-point task `opus` and `medium`; `speed` prints both medians, and "built → done" is under
   10 minutes.
5. **Updates:** after `update --all`, each of the four other projects is on the new version with one
   `chore(polaris): POLARIS … → …` commit and a clean tree, or a one-line reason why not.
6. **Phase 3:** the `land-race` golden goes red before the fix and green after; with
   `landing: self` back, a two-lane wave in the practice shop loses no task.
7. Every phase ends with `bash ops/polaris finish` exiting 0.

## How it runs after you approve
- **Switch this chat to Opus first** (`/model opus`). The plan is written so Opus and Sonnet can run
  all of it; there is no reason to spend Fable's weekly limit on waiting and landing.
- This chat is the conductor. Until task E ships, I size each helper by hand from `route`
  (Sonnet low / Opus medium / Opus high). Nothing waits on you mid-run; anything that would is
  parked and listed in the close.
- Budget: the three phases total about 3.5 hours inside one 360-minute run, with a clean stop after
  each release. A stop hands you a paste-ready "continue".
- The approval covers commits, pushes, tags, publishing, proof branches on GitHub, and updating and
  committing inside your other four POLARIS projects (Phase 2 and 3, `update --all`).
- **Optional, yours only** (I cannot change security settings): excluding Git's `usr\bin` folder
  and your temp folder from Defender's real-time scan would likely speed every command here; I have
  not measured it.
- This plan is saved to `plans/minutes.md`.
