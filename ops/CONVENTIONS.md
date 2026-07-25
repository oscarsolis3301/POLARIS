# CONVENTIONS
base: main                  # base branch
claim: local-lock           # one machine, many sessions — file lock, no network round-trip
integration: batch          # suite MEASURED 820s / 13.7min (.polaris/last-suite-seconds 2026-07-25) — NOT the ~3min this line claimed until then; far over paranoid's <2min rule — and sprint-4 per-land coverage was selftest-only anyway. Batch = full suite once per wave + final qa; a red land is found by the bisect recipe. If the harness denies `build:` invoked directly (both shells, sprint 4), the human-approved fallback (2026-07-20) is the repo's own gate `bash ops/polaris qa`; record the reduced per-land coverage in the burndown. If the gate is ALSO denied, STOP and ask the human — never route around a denial by any other means. Revisit if kickbacks appear.
voice: standard             # plain, friendly English when talking to the human
autolaunch: wt              # Planner opens a Builder pane per ready task in Windows Terminal, beside you
stale_hours: 1              # sweep warns on active locks older than this — build avg 0.2h (n=28); an hour-idle lock is a dead lane, not a slow one (sprint 4: 2 subagent stalls + 1 API-error death)
test: bash kit/ops/polaris doctor --selftest
test_fast: bash kit/ops/polaris doctor --selftest --only fmlist,tcm,brain,grant
# ^ the BUILDER's pre-handoff gate. MEASURED 2026-07-25: spine+1 drill 144s · this 4-drill subset
# 320s · full suite 820s. A 61% cut, and critically it lands UNDER the harness's 600s tool ceiling,
# so it COMPLETES instead of timing out and being re-run. Budget when editing this list: 144s of
# unskippable spine (verification-tiering.md:17-19) + ~44s per drill — drills are NOT free, so keep
# the subset to four and re-measure if you add one.
# (ops/contracts/verification-tiering.md: "check what changed
# often, prove everything once"). `test:` above is the WAVE gate — `qa`, the integrator, and CI
# still run it in full, so no gate disappears; a defect only the full drill catches now surfaces
# one wave later instead of one task later. That is a deliberate trade, made because `test:` is
# MEASURED at 820s (.polaris/last-suite-seconds) against the harness's 600s tool ceiling — every
# foreground full-suite run was timing out, returning nothing, and being re-run.
# Subset choice is NOT arbitrary: it excludes `rules` and `qa`, which the Learned log records as
# fixture-coupled (`rules` leaves a contract-less ready task that only an intervening `drift` drill
# masks). Adding either without `drift` produces FALSE reds — and a false red costs a whole fix wave.
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
drain: plan                 # plan | queue | backlog. CHANGED DEFAULT: one "go" authorizes the plan the human just approved, not the whole ready queue. Dependency chains inside the plan still loop automatically
run_max_tasks: 12           # tasks a single run will BUILD (0 = unbounded)
run_max_minutes: 90         # wall clock since kickoff; checked at wave boundaries only, never mid-task
run_max_agents: 20          # cumulative subagent spawns per run
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
1. bump `kit/ops/VERSION` (human only — it is what tells every installed kit a new POLARIS exists)
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
| burndown row + Learned log | Integrator | ops/SPRINT.md |
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
