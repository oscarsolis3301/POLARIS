# CONVENTIONS
base: main                  # base branch
claim: local-lock           # one machine, many sessions — file lock, no network round-trip
integration: batch          # TWO different numbers, do not conflate them (re-measured 2026-07-25, 5.19.0): `test:` alone = 805s/13.4min · the whole `qa` loop (test+build+uat, what `.polaris/last-suite-seconds` stamps) = 1225s/20.4min. This line used to cite 820s AND last-suite-seconds as one figure; they were never the same thing, and the gap only widened as uat: grew. Either way far over paranoid's <2min rule — and sprint-4 per-land coverage was selftest-only anyway. Batch = full suite once per wave + final qa; a red land is found by the bisect recipe. If the harness denies `build:` invoked directly (both shells, sprint 4), the human-approved fallback (2026-07-20) is the repo's own gate `bash ops/polaris qa`; record the reduced per-land coverage in the burndown. If the gate is ALSO denied, STOP and ask the human — never route around a denial by any other means. Revisit if kickbacks appear.
voice: standard             # plain, friendly English when talking to the human
autolaunch: wt              # Planner opens a Builder pane per ready task in Windows Terminal, beside you
# --- model_* REMOVED 2026-09-15 (owner). POLARIS names NO model; every spawn inherits the session's,
# so spend is controlled in exactly one place: /model. Reinstating any of these is refused by
# ops/RULES.tsv, and `fable`/`haiku` are refused by kit code regardless (core.sh model_denied).
# WHY: `model_strong: fable` + `route` returning strong for every PLANNER/INIT/INTEGRATOR/EVOLVE/
# CONDUCTOR role and every task at 5pts-or-risk sent ~12 subagents to Fable in ONE day, several over
# 300k tokens. Fable bills a SEPARATE, much smaller weekly limit — it hit 87% on work nobody asked to
# run there. The 2026-08-02 note below is superseded; it is kept so the reversal is legible.
# model_strong: fable         # owner decision 2026-08-02: fable carries planning, integration and every hard task (5pts or risk≠normal)
# model_mid: opus             # opus carries ordinary execution — the everyday builder tier (2-3pts)
# model_cheap: sonnet         # sonnet carries the cheap tier (1pt). NEVER haiku — 2026-08-02; now enforced in kit code, not prose
stale_hours: 1              # sweep warns on active locks older than this — build avg 0.2h (n=28); an hour-idle lock is a dead lane, not a slow one (sprint 4: 2 subagent stalls + 1 API-error death)
test: bash kit/ops/polaris doctor --selftest --parallel 3
test_fast: bash kit/ops/polaris doctor --fast
# ^ TWO tiers, and the split is the whole point ("check what changed often, prove everything once",
# ops/contracts/verification-tiering.md). MEASURED 2026-09-08 on this machine (Windows/Git Bash):
#   doctor --fast                        54 checks · 3s tier, 6s wall (doctor's env check is ~3.2s of it)
#   doctor --selftest --parallel 3       34 drills in 3 shards of 11-12 · 729s wall on a BUSY box
#                                        (169-378s is the quiet-box range measured earlier the same
#                                        day). Sharding does not make the suite cheap, it makes it
#                                        finish: still ~40% of serial, and on a loaded box it can
#                                        cross the 600s tool ceiling — run it via `bg run test`,
#                                        never a foreground call, when other lanes are working
#   doctor --selftest (serial)           805s — NOT re-measured here, the 2026-07-25 number stands;
#                                        the whole `qa` loop (test+build+uat) 1225s, same audit
# WSL: no distribution installed on 2026-09-08 (`wsl.exe -l` — "no installed distributions"), so the
#   Linux comparison could not be run; installing one is the human's call, not this task's. Git Bash
#   baseline: one git subprocess costs 57ms (measured: 20 calls, 1145ms) vs ~5ms on Linux, and the
#   suite is 394 `polaris` invocations across kit/ops/lib/selftest/*.sh — it is SPAWN-bound, not
#   logic-bound, which is why sharding helps and why Linux would help more.
#   Re-measure with: wsl bash kit/ops/polaris doctor --selftest --parallel 3
# `test_fast:` is the per-change gate: the in-process tier — pure functions, no CLI re-invocation, no
# throwaway git repo (ops/contracts/fast-tier.md). Seconds, so it runs on EVERY change. It sits
# BESIDE the drills, never instead of them. The old `test_fast:` was a 4-drill subset at 320s; that
# is 50x this tier's cost for a fraction of its assertions. Do not put drills back in this slot —
# add sections inside `selftest_fast` instead.
# `test:` is the WAVE gate, paid ONCE: by `qa`, by the integrator, by `finish`. An express land
# stamps `.polaris/suite-stamp` with HEAD (6.3.0), so a following `finish` skips the suite instead of
# paying it twice. Sharding trades CPU for wall clock — each shard pays its own ~144s spine — which
# is why the honest instruction for this gate is `bash ops/polaris bg run test` + chunked `bg wait`,
# NOT a foreground call: a foreground run that crosses 600s returns nothing at all and gets re-run,
# which is exactly how the serial 805s suite used to burn whole waves.
# CI still runs the FULL SERIAL drill on three OSes, so no coverage is lost by sharding here.
# Budget when adding a drill: ~44s each, spread across 3 shards — re-measure this line if you add one.
build: python kit/ops/pack.py --allow-dirty
lint:                       # none — bash + python, no package manager
typecheck:                  # none
uat: bash kit/ops/polaris check
# ^ golden-output acceptance (ops/tests/<name>.cmd vs <name>.expected). Rides the EXISTING uat:
# slot that `qa` already loops over, so qa needs no change and verification-tiering.md needs no
# amendment. This is the tier that replaces an agent re-checking behavior by hand every wave:
# write the pair once, then it costs a subprocess forever after. Add a golden whenever a bug
# escapes — that is how the suite grows without anyone budgeting time to "write tests".

# --- run bounds (2026-07-25 token/wall-clock audit) — a loop with no ceiling is not autonomy ---
autonomy: trusted           # owner decision 2026-08-03: composes plan_gate=auto · builder_questions=default-safe · evolve_apply=auto-reversible. These four knobs shipped in 5.13.0 and were never set here, so every run since has been paying the pre-5.13 gates — confirm at every plan, every spec ambiguity returned, every EVOLVE amendment queued. The hard gates are untouched and no knob softens them: risk: high approval, the STOP-AND-ASK list, RULES.tsv, the ready gate, contract-before-code, green-before-review. Explicit per-knob values still beat this line in both directions
drain: plan                 # plan | queue | backlog. CHANGED DEFAULT: one "go" authorizes the plan the human just approved, not the whole ready queue. Dependency chains inside the plan still loop automatically
run_max_tasks: 24           # tasks a single run will BUILD (0 = unbounded) Raised 12→24 by owner decision 2026-09-01 for the 6.2.0 program (20 approved tasks, 4 waves); revisit downward after 6.2.0 ships
run_max_minutes: 360        # wall clock since kickoff; checked at wave boundaries only, never mid-task. Raised 90→180 by owner decision 2026-08-04, mid-run and deliberately: the 6.0.0 program is ~2h of waves plus a full qa, so 90 stopped it cleanly halfway two runs running. 180 is sized to "one program, one run", not to "no ceiling" — the point of this block is still that a loop without a ceiling is not autonomy. Revisit downward once 6.0.0 ships; a routine sprint should not need this much Raised 180→360 by owner decision 2026-09-01 for the same program
run_max_agents: 40          # cumulative subagent spawns per run Raised 20→40 by owner decision 2026-09-01 for the 6.2.0 program (20 tasks + planner, integrators, evolve); revisit downward after 6.2.0 ships
run_fix_waves: 2            # was hard-coded in CONDUCTOR step 6.5
qa_scout: auto              # auto | off | always. auto spawns the scout ONLY when uat: is empty AND the run touched a runnable: path. runnable: unset ⇒ off
runnable:                   # globs of this repo's runnable surface. Deliberately UNSET: `test:` already drives the whole CLI end-to-end across 18 drills, so a scout here is pure duplication

branch format: feat/<ID> · integration branch: integrate/<date>
commit format: type(scope): message   # types: feat fix chore test docs
Definition of Done: acceptance boxes checked · `test:` green · `build:` green · `polaris verify` green

## THE SPLIT — read this before you touch anything
This repo IS POLARIS, and it RUNS POLARIS. Those are two different trees and confusing them is the
one mistake that costs real work:

| | `kit/` | `ops/` |
|---|---|---|
| what | the PRODUCT — every file that ships to users | the INSTALLATION — the board you are standing on |
| edit it? | yes, this is where all work happens | NEVER by hand (RULES enforce it) |
| how it changes | you write code | `python kit/ops/pack.py --dogfood` installs a published release |
| ships to users? | yes | no — `pack.py` only ever packs `kit/` |

Every kit file exists twice: `kit/ops/polaris` (source) and `ops/polaris` (installed). Edit the
installed copy and the work is lost the next time we install a release — and until then the board is
running code that exists nowhere in the source. `ops/RULES.tsv` blocks it at write time and names the
source file to edit instead.

The installed instance also LAGS the source: mid-sprint, `kit/ops/` docs and role files describe
behavior the installed CLI does not have yet. When they disagree, the installed CLI plus
`ops/MANUAL.md` are the truth for board mechanics until the next dogfood — check
`bash ops/polaris version` before following any recipe that landed this sprint.

The board (`ops/board/`, `ops/contracts/`, and this file) IS state, and is written normally.

## Release ritual — a release is not done until we run it ourselves
**Whose job: the assistant's, end to end.** Owner decision 2026-08-04, extending the 2026-07-15
lift of the `kit/ops/VERSION` rule (`ops/RULES.tsv`). An approved plan that reaches its end carries
the release with it — all five steps below, without a second ask. Reaching the end means the board
is drained and `bash ops/polaris finish` exited 0; a run that stopped short of that has not earned a
release. `risk: high` approval, the STOP-AND-ASK list and every RULES line still bind as always.
**SCOPE — read this before generalizing it.** This paragraph is about THIS repo publishing ITSELF.
It lives in `ops/CONVENTIONS.md` and `ops/RULES.tsv`, the two files `install.sh` refreshes never
(`install.sh`: "board, RULES, CONVENTIONS, MAP, SPRINT untouched"), so it cannot and must not reach
a repo that merely *has* POLARIS installed. POLARIS in someone's project never bumps their version,
never tags them, never publishes them, and never touches their config — it does the board work its
role files describe and nothing more. Do not port this to the kit; there is nothing here to ship.
1. bump `kit/ops/VERSION` — it is what tells every installed kit a new POLARIS exists
2. CHANGELOG entry, same version
3. commit · `git tag vX.Y.Z && git push --tags` — CI builds and publishes the zip
4. **`python kit/ops/pack.py --dogfood`** — downloads the PUBLISHED zip, installs it here, runs the
   board's selftest. This is the only test that walks the path a stranger walks.
5. commit the refreshed `ops/`

The daily CI job fails if `ops/VERSION` ≠ the latest published release — i.e. if we shipped something
we never ran. Skipping step 4 also leaves `main`'s tarball and the raw channel URL serving the OLD
kit to everyone who installed before the `kit/` split existed.

## Write routing — one fact, one home (a fact in two files means one is drifting)
| Fact | Only writer | Only home |
|---|---|---|
| burndown row | `seal` (from 6.5.0 — the Integrator by hand while the installed CLI is older) | ops/SPRINT.md |
| Learned bullet | any lane, via `polaris learned -m` (from 6.5.0); EVOLVE prunes to ≤5 | ops/SPRINT.md |
| MAP content | Integrator (via task map_delta) | ops/MAP.md |
| conventions values + Planner calibration notes | EVOLVE (human-approved) | this file, § Planner calibration (ops/roles/ is a RULES-guarded installed copy here) |
| RULES lines | human (EVOLVE proposes) | ops/RULES.tsv |
| task truth | the board scripts | ops/board/** frontmatter |
| kit code + invariants | human only | kit/CLAUDE.md · kit/ops/polaris · kit/ops/dashboard.py · kit/ops/hooks/ |
| the installed instance | `pack.py --dogfood` only | ops/ (never hand-edited) |

## Planner calibration (appended by EVOLVE, human-approved; Planner reads before pointing)
- 2026-07-18 · Ignore the 3pt p50 30.4h bucket (n=1 = T-002): review parking during the off-board-edit collision, not build effort (build split avg 0.1h). Do not point up 3-pointers from it.
- 2026-07-18 · Points do not predict wall-clock here (5pt p50 = 2pt p50 = 0.5h, n=8, 0 kickbacks); they predict scope and merge risk. Wave capacity is planning-bound (carve quality), not build-bound.
- 2026-07-20 · Two carve patterns held at 0 kickbacks across 6 sprint-4 waves (T-020..T-028): (a) serial-chain the hotspot file; run contract-sourced doc tasks parallel to the chain; (b) parallel wording tasks need no depends_on — pin the exact phrase in the contract (T-027/T-028 both cite "already fast-forwarded", merged zero-conflict).
- 2026-07-20 · Lanes up to 5 when ready tasks are fully disjoint (evidence: 0 kickbacks n=29 at 3 lanes; disjointness held every wave).
- 2026-07-20 · Suite outgrew the harness: full selftest ~3min→~7min over sprint 5; under parallel lanes it crossed the 600s tool cap — lanes died of timeout mechanics, not bad code (T-033 rescue: stalled draft was 100% correct; T-038, which carried the timeout note, finished clean). Every CLI task: (a) end `verify:` with `doctor --selftest --only <drill-label>` instead of the full suite — the full suite still gates handoff (`test:`) and the wave, so no gate weakens, and Integrator run-verify stops re-running ~7min per task; (b) copy into the task's Notes: run long suites FOREGROUND with an explicit ≥600s timeout; if the harness caps it, log to a file and poll for the `selftest passed` line.
- 2026-08-04 · Two reflexes earned in sprint 10, copy them into every CLI task's Notes: (a) SCRATCH DIRS ARE PER-LANE — parallel builders share one scratchpad, and one lane's `rm -rf` of a bare shared path (`scratchpad/sab`) deleted another lane's in-use fixture tree mid-selftest (W4: T-080 vs T-050), fabricating a spine red that reads exactly like a regression (SECOND-SEAL LAND FAIL); namespace every scratch path `scratchpad/<ID>/…`, never delete a shared scratch path another lane might be standing in, and treat a failure point that MOVES between runs as corruption, not code — a real regression fails identically every time, so re-run in a clean dir before believing it. (b) A SABOTAGE GREEN COUNTS ONLY AFTER READING THE SABOTAGE DIFF — an off-by-one sed is a no-op whose restore-green is vacuous (two no-op sabotage edits caught by diff in one wave); verify the edit took, watch the red, then restore — and any sabotage evidence from a possibly-corrupted run is re-proven in a clean directory.
- 2026-08-03 · Three rules earned across sprints 7–10: (a) get the `risk: high` merge-yes AT THE PLAN GATE, never at the merge — T-047 waited 128.9h at the gate with 13 of 28 pts stalled behind it and `ready/` empty (integrate avg 1.5h→3.9h on gate wait alone); sprint 10 named T-048's approval up front and it merged same-day. (b) A Builder-found defect outside its ownership is a first-class task source: file a 1-pt, single-disjoint-file rider into the wave in flight (T-072, T-073 — both landed same-wave, one point each), never an IDEAS.md line that ages until the repro is forgotten; a one-file rider clears the ready gate without re-planning the wave, and the Integrator holds the gate to take the rider rather than sealing early. (c) NEVER YAML-quote a `verify:` line — frontmatter-lists v1 keeps quotes by design, so a double-quoted entry reaches bash as ONE quoted word and can never run (T-074 shipped two unrunnable assertions); plain unquoted lines are always right, no quoting is ever needed.
- 2026-09-14 · A CROSS-LANE GOLDEN OWNER'S `verify:` NEVER CARRIES A STRICT DIFF OF THE DERIVED GOLDEN. The wave's `ops/tests/api-kit.expected` owner writes rows for sibling lanes' symbols from the CONTRACT's pinned names, but its worktree is based on `<base>` and cannot index a function a sibling has not landed — so `find --api … | diff - ops/tests/api-kit.expected` is unsatisfiable by construction until the sibling lands, and merging the wave branch in trips check_ownership. Carve it the way T-136's line 10 had to be amended: `grep -q` that each pinned sibling row is PRESENT, and diff with exactly those rows excluded from BOTH sides; the strict diff runs at the wave gate (`check` once every lane has landed) and in CI's serial run. A task whose rows are all its own keeps the strict line (T-134: nine rows, all its own). Evidence: sprint 13's owners T-122/T-125 were carved WITHOUT the strict line — 0 round trips; sprint 14's T-136 was carved WITH it — one conductor round trip to amend a line no command can amend (`grant` widens `files_owned`; nothing widens `verify:`), and the trip is unmetered: kickbacks 7d = 0.
- 2026-09-14 · DEPENDENCY-CHAIN PROMOTION IS ONE COMMAND — `bash ops/polaris next --do` — NEVER A HAND MOVE. It holds every `backlog/` task to the full ready gate (deps in `done/` · contract exists · points ∉ {8, 13, ''} · no unapproved `ask` scope · `files_owned` disjoint from `ready/` ∪ `active/`) under the board lock and lands ONE `chore(board): promote <IDs>` commit; `next` printing `promote` on line 1 means exactly "run `next --do`", and INTEGRATOR.md § 5 already says so — CONDUCTOR.md step 7 does not (the role-file fix is queued in IDEAS.md for a human). Sprint 14 spent a whole planner context moving T-135/T-136/T-137 between folders for what the command does in one commit (board ref 1f63e9c, six minutes after T-134 landed). Two things to know while the kit catches up: the pass does not filter on `plan:` (the build scan does — a foreign task lands in `ready/` but is never built under `drain: plan`), and a candidate can be dropped SILENTLY on three of the five gates (T-130's IDEAS note) — an expected ID missing from both `promoted:` and `held:` means re-check those gates by hand, never a hand move.
- 2026-09-17 · A GOLDEN PAIR IS PINNED BEHAVIOR THAT NO AUTOMATIC GATE RUNS — WHOEVER CHANGES THE BEHAVIOR OWNS THE RE-PIN, IN THE SAME TASK. The 31 pairs in `ops/tests/` execute in exactly three places, all through `uat: bash ops/polaris check`: `qa`, `land --express` and `finish`. CI runs `doctor --selftest` ONLY (`.github/workflows/ci.yml` — no `polaris check` step anywhere), and `test_fast:`, the gate every builder pays on every change, contains no golden at all. Between wave gates a stale pin is therefore invisible. Evidence: the 2026-09-15 model ban changed two things goldens pinned and re-pinned neither; both sat red for two days and cost sprint 16 two whole tasks to repair — T-162 (`rules-health.expected` pinned 16 rules against 17) and T-172 (`route-tier.expected` pinned a model name the CLI now refuses). PLANNER: when a task changes a RULES line, a KEYS row, a help line, a refusal message, or any printed count, grep `ops/tests/*.expected` for it AT CARVE TIME and put the re-pin in that task's `files_owned` and `verify:` — a repair task next sprint is the expensive spelling of the same fix. The kit-side fix (`check --changed`, or running a task's touched goldens at handoff) is logged in `ops/board/backlog/IDEAS.md` for a human; until it exists, the carve IS the gate.
- 2026-09-17 · `check --only` AND `find --api` ARE PRIMARY-ANCHORED, SO THEY PASS VACUOUSLY FROM A BUILDER WORKTREE — NEVER PUT THE BARE FORM IN A `verify:`. Both anchors are deliberate: `cmd_check` reads `$OPS/tests` and runs every `.cmd` under `cd "$PRIMARY"` (observe.sh), and `index_root` is `git worktree list --porcelain | sed -n '1s/^worktree //p'` because only the primary holds `.polaris/index.db` (search.sh). From `.polaris/wt/<ID>` that means three different vacuous passes: a NEW pair is not in the primary's `ops/tests/`, so `check --only <name>` prints `no goldens matched` and exits 0 — green, having asserted nothing; an EXISTING pair runs the primary's code and cannot see the builder's change; and `find --api` indexes a tree without the builder's new functions. Sprint 16 had several lanes rediscover this independently and each hand-roll the same two workarounds — the signature of a rule that belongs in the carve rather than in each builder's head. PLANNER: write the worktree-true forms into the task's Notes instead (both verified here 2026-09-17) — `bash ops/tests/<name>.cmd 2>/dev/null | diff - ops/tests/<name>.expected` runs the golden against THIS worktree (the `2>/dev/null` matches exactly what `cmd_check` captures), and `POLARIS_ROOT="$PWD" python ops/index.py find --api <glob>` indexes it (`POLARIS_ROOT` is index.py's documented override). The primary-anchored form is correct at the WAVE gate, after landing; keep it there. Same family as the 2026-09-14 cross-lane-golden note above, and as the Learned bullet "A VERIFICATION REQUIREMENT MUST NAME A CALLER WHO CAN ACTUALLY RUN IT".

## Kit changelog
- 2026-07-18 · MAP folded: header re-dated, CLI row gains clean-history commands, selftest-install/selftest-dashboard promoted to Modules, dashboard Unverified bullet cleared, Deltas emptied · 3 Deltas lines (T-001, T-003, T-007) + T-003 clearing the untested-dashboard claim
- 2026-07-18 · SPRINT Learned pruned to ≤5: dropped the zero-conflict/paranoid-cost bullet · content institutionalized in CONVENTIONS integration comment + MAP hotspots
- 2026-07-18 · Calibration home moved to this file (§ Planner calibration) with two notes; write-routing row updated; fallback-home gap logged to IDEAS · ops/roles/ is RULES-guarded here, blocking EVOLVE's kit-default target (PLANNER.md §Pointing); metrics n=8, 0 kickbacks, T-002 30.4h outlier
- 2026-07-18 · SPRINT Learned pruned 9→4: dropped write-guard-prefix, off-board-collision, stale 5.11-lag, integrate-lag, seal-blocked bullets; merged the two seal/fold bullets into one corrected installed-vs-source bullet · drift finding LEARNED 9>5; waves 2-6 all folded via MANUAL fallback, sprint 3 complete
- 2026-07-18 · integration: paranoid comment rewritten with real suite cost (~2-3min), keep-rationale (zero-bisect red lands) and revisit triggers (>5min suite or >5-task waves) · 6 paranoid waves this sprint, 0 kickbacks; old comment claimed 15s
- 2026-07-18 · THE SPLIT gains installed-LAGS-source paragraph: installed CLI + ops/MANUAL.md are board-mechanics truth until the next dogfood · sprint 3 ran installed 5.12.0 against kit 5.13.0-unreleased; T-017 seal recipe unrunnable, 5 waves needed MANUAL fold
- 2026-07-20 · stale_hours 4→1 · build avg 0.2h (n=28); sprint 4's stale locks were dead lanes (2 subagent stalls + 1 API-error death), not slow builds
- 2026-07-20 · integration comment codifies the classifier-safe fallback (build: via bash ops/polaris qa at the wave gate, reduced per-land coverage recorded in burndown); kit-entrypoint gap logged to IDEAS · build: classifier-blocked in both subagent shells all sprint 4, 6 waves ran selftest-only per land
- 2026-07-20 · integration: paranoid → batch · suite ~3min over paranoid's <2min rule; per-land coverage was selftest-only anyway; batch = full suite once per wave + final qa, red lands found by the bisect recipe; revisit if kickbacks appear
- 2026-07-20 · Planner calibration gains the two sprint-4 carve patterns; SPRINT Learned pruned 8→5 (carve-pattern ×2 + classifier/pack bullets institutionalized) · 0 kickbacks across 6 waves T-020..T-028; T-027/T-028 merged zero-conflict on a contract-pinned phrase
- 2026-07-20 · integration fallback clause reworded human-anchored: denial → approved qa gate; gate also denied → STOP and ask, never route around a denial · harness security review flag; wording only, no behavior change
- 2026-07-20 · Planner calibration: lanes up to 5 on fully disjoint ready tasks · 0 kickbacks n=29 at 3 lanes, disjointness held every wave (approved 5.15.0 plan)
- 2026-07-21 · Planner calibration gains the selftest-vs-harness note: CLI tasks end `verify:` with `doctor --selftest --only <drill-label>` + a Notes timeout recipe (foreground ≥600s, else log-and-poll) · suite ~3→~7min over sprint 5; T-033 lane died of the 600s tool cap with a 100% correct draft; T-038, carrying the note, finished clean
- 2026-07-21 · SPRINT Learned pruned 7→4: dropped 5.14-lag + backlog-promotion (stale — 5.15.0 dogfooded; MANUAL institutionalizes the promotion pattern) and rescue-lane (institutionalized by the new calibration note) · carry-overs: bash-3.2, stale-zip, local-expansion, pipelined-landing
- 2026-07-21 · clean-history contract gains v2.3: per-stream clarification of v2.2(b) — land captures BOTH streams of the squash merge, re-emits captured stderr on conflict/failure · T-038 Notes: git-for-Windows 2.53 splits the two squash notes across stdout/stderr; documents shipped behavior, no code change
- 2026-08-03 · MAP folded: header re-dated; Entry points gain the kit/ops/lib/ row (workspace + bg modules included); Modules gain PROTOCOL.md + KEYS.tsv rows, roles row gains SOLO·CONDUCTOR, templates row gains ROADMAP.md; new § Board mechanics + § CLI surface absorb the board-ref/seal/publish/report/autonomy-default and command facts; Hotspots gain the module-split chaining rule + the `api-kit.expected` one-owner-per-wave rule; "one thing" gains the 27-vs-21 kit-vs-installed drill-label tell; Deltas emptied · 21 Deltas lines (T-013..T-048, 5.13→6.0), drift finding [1]
- 2026-08-03 · SPRINT Learned pruned 9→4: risk-high-root, 1-pt-rider and verify-quoting bullets → § Planner calibration above (their new home); suite-shards/kit-anchor bullet → already in test:/test_fast measured comments + THE SPLIT lags paragraph + the new MAP label-tell line (its `--parallel 3` promotion queued as an EVOLVE proposal); lock-owner-check bullet → shipped code (T-064 pid-guard) + shared-checkout.md v1.1 + the claimguard/busyint drills; EOL bullet compacted (live remainder: five pre-existing reports each owe one whole-file diff); bg bullet gains sprint 10's second orphaned-job instance + the `finish`-exceeds-ceiling gap · drift finding [2]
- 2026-08-03 · Planner calibration gains the sprint-7–10 triple note (risk-high yes at the plan gate · 1-pt rider · never quote `verify:`) · T-047 128.9h gate wait vs T-048 same-day; T-072/T-073 same-wave riders; T-074 two unrunnable assertions
- 2026-08-04 · MAP folded: header re-dated; drill-label tell corrected "27 vs 21" → kit 28 vs installed 27 + a recount-don't-trust clause (SELFTEST_LABELS recounted first-hand in both spine.sh copies); install.sh row gains the § 6 hook-merge repair; Board mechanics gains the 6.0 discovery loop + BREAKING banner; CLI surface gains `adopt`; Deltas emptied · 4 Deltas lines (T-076/T-077/T-078/T-080), stale-count finding in the W4 burndown row
- 2026-08-04 · output-style.md gains § v3: the widened plain-voice jargon alternation (suites?|merge[ds]?|branch(es)?|…) recorded as authoritative, never to be narrowed; v3 wins where v2's assertion-6 spelling disagrees · T-082, the program's one kickback — § v2 still specified the pre-widening grep, the worked examples' only guard
- 2026-08-04 · SPRINT Learned pruned 7→5: EOL bullet dropped (closed; live remainder — five pre-existing reports each owe one whole-file diff — stays recorded in the 2026-08-03 line above); plain-voice-kickback bullet dropped (institutionalized by § v3 + the .cmd header note) · drift finding "EVOLVE next" in the W5 burndown row
- 2026-08-04 · Planner calibration gains the sprint-10 reflex pair (per-lane scratch namespacing · sabotage-verified-by-diff) as the lessons' permanent home · one real cross-lane fixture deletion (W4) + two no-op sabotage edits caught only by reading the diff
- 2026-08-23 · SPRINT Learned pruned 10→5: bg-orphan bullet dropped (absorbed — bg.sh machinery + PROTOCOL § LONG COMMANDS + the bg-recipe now standard in every kickoff; live remainder queued as a proposal: the integration comment above never names `finish` as qa-class though it re-runs the suite internally); scratchpad bullet dropped (absorbed 2026-08-04 into § Planner calibration, its permanent home); the four golden-family bullets merged into ONE earned-discipline bullet (one-owner-per-wave · pin-by-surface-KIND incl. KEYS.tsv rows · content-diff refresh scope, never commit range · primary-anchored `check` vacuity); base-bound-commit bullet compacted; kept whole: rc-not-prose (T-089) · caller-with-context (T-087) · fail-closed-beats-fixture-churn (T-088) · drift finding [1], reported by three consecutive integrators
- 2026-08-23 · MAP folded: header re-dated; label tell corrected (kit 28 vs installed 27 at 5.24.0 → 31 = 31 since the 6.1.0 dogfood, recount clause kept); ownership-guard row gains primary_gate, new checkout-guard.sh row; Board mechanics gains the 6.1 enforced-isolation facts (landing key · lease holder IS the Integrator · ready∪active disjointness · drift --strict · self_land refusals); CLI surface gains the three new drill labels + two goldens; Deltas emptied · 5 Deltas lines (T-084..T-089)
- 2026-09-14 · MAP folded: header re-dated; label tell corrected (31 = 31 at the 6.1.0 dogfood → 35 = 35 since the 6.3.1 dogfood, recount clause kept); Entry points gain the search/awake/handover modules, the beat + wt_remove primitives, the guards' 6.2 verbs and rows for handover-hook, awake-hook + presser, update-hook and commit-msg; Modules gain VISUAL.md + the 6.1–6.4 KEYS rows; the release section gains `update --auto`; Board mechanics gains 6.2 liveness + handover, 6.3 fast tier + auto-update, 6.4 surfaces; CLI surface gains next/awake/update/surfaces/qa flags + the 35-label list; Danger zones synced to `polaris rules` (ops/lib/, ops/index.py, ops/KEYS.tsv, ops/PROTOCOL.md); Hotspots gain the co-change counts, the roles trio and the verify corollary; Deltas emptied · 22 Deltas lines (T-092..T-136, 6.2→6.4), drift finding [1] — the one finding keeping qa red on base
- 2026-09-14 · Planner calibration gains the cross-lane-golden verify rule (assert pinned sibling rows present, diff with them excluded from both sides; the strict diff waits for the wave gate) · T-136 verify line 10 amended by a conductor message (its Notes), where T-122/T-125 had been carved without the line at 0 round trips; kickbacks 7d = 0, so the round trip never reached metrics
- 2026-09-14 · Planner calibration gains the promote-is-one-command note (`next --do`, its five gates, its two known gaps) · sprint 14: one planner context spent hand-moving T-135/T-136/T-137; the board shows the pass as one commit (1f63e9c) six minutes after T-134 landed; INTEGRATOR.md § 5 names the command, CONDUCTOR.md step 7 does not (kit prose — IDEAS.md, human)
- 2026-09-17 · MAP folded: header re-dated; the label tell recounted first-hand in both `lib/selftest/spine.sh` copies (35 → 37 = 37 at the 6.5.0 dogfood; sprint 16 added NO drill — the gallery shipped as the `shots-gallery` GOLDEN) and gains the 31-goldens-run-nowhere pointer; entry row corrected to 433 lines with the real loader list and the 6.5/6.6 verbs, its `qa)` known-bug clause retired (fixed by T-158); lib row gains surfaces · skills · visual with their fns and contracts; bootstrap row gains arm_machine's output-style + i-have-adhd; templates row gains SKILL.md + DESIGN.md; KEYS row gains adhd · gallery · column 5 `ask` + `interview`; VISUAL row rewritten for visual-check § v2 (two captures, never filenames) and the deliberate absence of a DESIGN.md guard; the CI row states it runs `doctor --selftest` only; Board mechanics gains 6.5 (skills shelf · amend · learned · seal burndown row · next_promote plan hold · cruft classes · board_pull · update --all) and 6.6 (screen slug · two captures · --saw · shots · the published gallery + the three carve constraints); CLI surface gains promote · interview · amend · learned · skill · shots and the 37-label / 31-golden counts; Hotspots gain sprint 16's five-task visual.sh chain and a new visual.sh size-cap bullet; Deltas emptied · 21 Deltas lines (T-138..T-169, 6.4→6.6), drift finding [1] — the one finding keeping `qa` red on base
- 2026-09-17 · Planner calibration gains the golden-re-pin-at-carve-time note · T-162 and T-172 were both repair tasks for goldens the 2026-09-15 model ban broke and left red for two days; ci.yml runs `doctor --selftest` only and `test_fast:` holds no golden, so nothing between wave gates could ever have caught them
- 2026-09-17 · Planner calibration gains the primary-anchored-verification note, with the two worktree-true recipes verified first-hand · several sprint-16 lanes independently hit the vacuous pass and each hand-rolled the same workaround; the failure is already half-recorded in SPRINT Learned ("`cmd_check` is primary-anchored, so a pair born in a worktree passes VACUOUSLY") and recurred anyway
